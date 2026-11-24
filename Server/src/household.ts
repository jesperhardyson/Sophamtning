import { DurableObject } from "cloudflare:workers";
import { randomB64url, sha256B64url } from "./encoding";
import { error, noContent, readObject } from "./responses";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const MAX_PARTICIPANTS = 10;
const INVITE_LIFETIME = { invite: 7 * DAY, migration: 90 * DAY };

type Purpose = keyof typeof INVITE_LIFETIME;

interface Participant {
  id: string;
  isOwner: boolean;
}

/** Ett hushåll: deltagarna, inbjudningarna och de krypterade posterna. Innehållet går inte att läsa här. */
export class Household extends DurableObject<Env> {
  private get sql(): SqlStorage {
    return this.ctx.storage.sql;
  }

  // MARK: Skapa

  async create(householdId: string): Promise<{ participantId: string; participantSecret: string }> {
    const secret = randomB64url(32);
    const secretHash = await sha256B64url(secret);
    const participantId = randomB64url(16);
    this.ctx.storage.transactionSync(() => {
      this.sql.exec(`
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE participants(id TEXT PRIMARY KEY, secretHash TEXT NOT NULL, isOwner INTEGER NOT NULL, joinedAt TEXT NOT NULL, removedAt TEXT, nameData TEXT);
        CREATE TABLE invites(tokenHash TEXT PRIMARY KEY, purpose TEXT NOT NULL, expiresAt TEXT NOT NULL);
      `);
      this.set("householdId", householdId);
      this.set("createdAt", now());
      this.set("seq", "1");
      this.sql.exec("INSERT INTO participants(id, secretHash, isOwner, joinedAt) VALUES (?, ?, 1, ?)", participantId, secretHash, now());
    });
    return { participantId, participantSecret: secret };
  }

  // MARK: Anrop

  override async fetch(request: Request): Promise<Response> {
    const [, , , , action = "", id = "", ...rest] = new URL(request.url).pathname.split("/");
    if (!this.exists()) return error(404, "not_found");
    const route = `${request.method} ${action}`;
    const ended = this.get("endedAt") !== null;
    if (route === "POST join" && !id) return ended ? error(404, "invite_invalid") : this.join(request);
    if (ended) return error(410, "ended");

    const me = await this.authenticate(request);
    if (me instanceof Response) return me;
    if (rest.length === 0) {
      switch (route) {
        case "DELETE ":
          return this.end(me);
        case "POST invites":
          if (!id) return this.invite(me, request);
          break;
        case "DELETE invites":
          if (!id) return this.revokeInvites(me);
          break;
        case "GET changes":
          if (!id) return this.changes();
          break;
        case "DELETE participants":
          if (id) return this.removeParticipant(me, id);
          break;
      }
    }
    return error(404, "not_found");
  }

  /**
   * Deltagaren bakom anropet. Bara den som visar rätt hemlighet och har tagits bort får svaret `removed`. Fel hemlighet är
   * `unauthorized`, som inte bevisar något.
   */
  private async authenticate(request: Request): Promise<Participant | Response> {
    const match = /^Bearer ([A-Za-z0-9_-]{22})\.([A-Za-z0-9_-]{43})$/.exec(request.headers.get("Authorization") ?? "");
    if (!match) return error(401, "unauthorized");
    const hash = await sha256B64url(match[2]!);
    const row = this.sql.exec<{ secretHash: string; isOwner: number; removedAt: string | null }>("SELECT secretHash, isOwner, removedAt FROM participants WHERE id = ?", match[1]!).toArray()[0];
    if (!row || row.secretHash !== hash) return error(401, "unauthorized");
    if (row.removedAt !== null) return error(403, "removed");
    return { id: match[1]!, isOwner: row.isOwner === 1 };
  }

  // MARK: Inbjudningar

  private async invite(me: Participant, request: Request): Promise<Response> {
    if (!me.isOwner) return error(403, "forbidden");
    const body = await readObject(request);
    const purpose = body?.purpose;
    if (purpose !== "invite" && purpose !== "migration") return error(400, "bad_request");
    const token = randomB64url(32);
    const hash = await sha256B64url(token);
    if (purpose === "migration") {
      const tooLate = Date.now() - Date.parse(this.get("createdAt")!) > DAY;
      if (tooLate || this.get("migrationInviteAt") !== null) return error(409, "migration_unavailable");
      this.set("migrationInviteAt", now());
    }
    const expiresAt = new Date(Date.now() + INVITE_LIFETIME[purpose as Purpose]).toISOString();
    this.sql.exec("DELETE FROM invites WHERE expiresAt <= ?", now());
    this.sql.exec("INSERT INTO invites(tokenHash, purpose, expiresAt) VALUES (?, ?, ?)", hash, purpose, expiresAt);
    return Response.json({ inviteToken: token, expiresAt }, { status: 201 });
  }

  private revokeInvites(me: Participant): Response {
    if (!me.isOwner) return error(403, "forbidden");
    this.sql.exec("DELETE FROM invites WHERE purpose = 'invite'");
    return noContent();
  }

  private async join(request: Request): Promise<Response> {
    const token = (await readObject(request))?.inviteToken;
    if (typeof token !== "string") return error(400, "bad_request");
    const tokenHash = await sha256B64url(token);
    const secret = randomB64url(32);
    const secretHash = await sha256B64url(secret);
    // Härifrån finns ingen await, så att två som går med samtidigt inte kan bli elva.
    if (this.get("endedAt") !== null) return error(404, "invite_invalid");
    const valid = this.sql.exec("SELECT 1 FROM invites WHERE tokenHash = ? AND expiresAt > ?", tokenHash, now()).toArray().length > 0;
    if (!valid) return error(404, "invite_invalid");
    const count = this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM participants WHERE removedAt IS NULL").one().n;
    if (count >= MAX_PARTICIPANTS) return error(409, "full");
    const participantId = randomB64url(16);
    this.ctx.storage.transactionSync(() => {
      this.sql.exec("INSERT INTO participants(id, secretHash, isOwner, joinedAt) VALUES (?, ?, 0, ?)", participantId, secretHash, now());
      this.bump();
    });
    return Response.json({ participantId, participantSecret: secret }, { status: 201 });
  }

  // MARK: Deltagare

  private removeParticipant(me: Participant, id: string): Response {
    if (!me.isOwner && id !== me.id) return error(403, "forbidden");
    if (me.isOwner && id === me.id) return error(409, "owner_cannot_leave");
    this.ctx.storage.transactionSync(() => {
      const removed = this.sql.exec("UPDATE participants SET removedAt = ?, nameData = NULL WHERE id = ? AND removedAt IS NULL", now(), id).rowsWritten > 0;
      if (removed) this.bump();
    });
    return noContent();
  }

  private end(me: Participant): Response {
    if (!me.isOwner) return error(403, "forbidden");
    this.bury("ended");
    return noContent();
  }

  /** Raderar allt utom det som behövs för att svara `ended`: id:t, orsaken och tiden. */
  private bury(reason: "ended" | "inactive"): void {
    this.ctx.storage.transactionSync(() => {
      const householdId = this.get("householdId")!;
      this.sql.exec("DELETE FROM participants; DELETE FROM invites; DELETE FROM meta;");
      this.set("householdId", householdId);
      this.set("endedAt", now());
      this.set("endedReason", reason);
    });
  }

  // MARK: Ändringar

  private changes(): Response {
    const participants = this.sql
      .exec<{ id: string; isOwner: number; joinedAt: string; nameData: string | null }>("SELECT id, isOwner, joinedAt, nameData FROM participants WHERE removedAt IS NULL ORDER BY rowid")
      .toArray()
      .map((row) => ({ id: row.id, isOwner: row.isOwner === 1, joinedAt: row.joinedAt, name: row.nameData }));
    return Response.json({ seq: Number(this.get("seq")), full: true, participants, records: [], deleted: [] });
  }

  // MARK: Lagring

  /** Ett hushåll som aldrig har skapats har inga tabeller, och ett anrop mot det lagrar ingenting. */
  private exists(): boolean {
    return this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'meta'").toArray().length > 0;
  }

  private get(key: string): string | null {
    return this.sql.exec<{ value: string }>("SELECT value FROM meta WHERE key = ?", key).toArray()[0]?.value ?? null;
  }

  private set(key: string, value: string): void {
    this.sql.exec("INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, value);
  }

  /** Ökar löpnumret med ett och svarar med det nya. */
  private bump(): number {
    const seq = Number(this.get("seq")) + 1;
    this.set("seq", String(seq));
    return seq;
  }
}

function now(): string {
  return new Date().toISOString();
}
