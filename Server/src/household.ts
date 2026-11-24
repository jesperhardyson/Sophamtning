import { DurableObject } from "cloudflare:workers";
import { randomB64url, sha256B64url } from "./encoding";
import { sendApns, sendFcm, type PushResult } from "./push";
import { error, noContent, readObject } from "./responses";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const MAX_PARTICIPANTS = 10;
const MAX_RECORDS = 200;
const MAX_DATA = 8 * 1024;
const MAX_NAME = 512;
/** Med tio deltagare ryms då alla push inom de 50 anrop som en körning får göra. */
const MAX_DEVICES = 4;
const DELETION_LIFETIME = 30 * DAY;
const INACTIVE_LIFETIME = 400 * DAY;
const INVITE_LIFETIME = { invite: 7 * DAY, migration: 90 * DAY };

type Purpose = keyof typeof INVITE_LIFETIME;

const DEVICE_ID = /^[A-Za-z0-9_-]{22}$/;
const APNS_TOKEN = /^[0-9a-fA-F]{64,200}$/;
const FCM_ID = /^[A-Za-z0-9_:-]{1,256}$/;
const RECORD_NAME = /^[A-Za-z0-9_-]{43}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;

interface RecordRow extends Record<string, SqlStorageValue> {
  name: string;
  kind: string;
  data: string;
  by: string;
  at: string;
  expiresAt: string | null;
}

interface DeviceRow extends Record<string, SqlStorageValue> {
  deviceId: string;
  platform: "apns" | "fcm";
  token: string;
  environment: "production" | "sandbox" | null;
  urgent: number;
}

/** Händelser som ger push. `urgent` är de som appen visar en notis för. */
type PushEvent = "urgent" | "quiet";

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
        CREATE TABLE records(name TEXT PRIMARY KEY, kind TEXT NOT NULL, data TEXT NOT NULL, by TEXT NOT NULL, at TEXT NOT NULL, expiresAt TEXT, seq INTEGER NOT NULL);
        CREATE TABLE devices(deviceId TEXT PRIMARY KEY, participantId TEXT NOT NULL, platform TEXT NOT NULL, token TEXT NOT NULL, environment TEXT, urgent INTEGER NOT NULL);
        CREATE TABLE deletions(name TEXT PRIMARY KEY, seq INTEGER NOT NULL, at TEXT NOT NULL);
      `);
      this.set("householdId", householdId);
      this.set("createdAt", now());
      this.set("lastActivity", now());
      this.set("seq", "1");
      this.set("prunedSeq", "0");
      this.sql.exec("INSERT INTO participants(id, secretHash, isOwner, joinedAt) VALUES (?, ?, 1, ?)", participantId, secretHash, now());
    });
    await this.scheduleAlarm();
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

    // Kroppen läses före behörigheten. Efter den väntar inget anrop, så att hushållet eller deltagaren inte hinner försvinna.
    const body = request.method === "PUT" || request.method === "POST" ? await readObject(request) : {};
    const me = await this.authenticate(request);
    if (me instanceof Response) return me;
    if (body instanceof Response) return body;
    this.noteActivity();
    const response = await this.handle(me, route, id, rest, request, body);
    await this.scheduleAlarm();
    return response;
  }

  private handle(me: Participant, route: string, id: string, rest: string[], request: Request, body: Record<string, unknown>): Response | Promise<Response> {
    if (rest.length === 0) {
      switch (route) {
        case "DELETE ":
          if (!id) return this.end(me);
          break;
        case "POST invites":
          if (!id) return this.invite(me, body);
          break;
        case "DELETE invites":
          if (!id) return this.revokeInvites(me);
          break;
        case "GET changes":
          if (!id) return this.changes(request);
          break;
        case "GET socket":
          if (!id) return this.openSocket(me, request);
          break;
        case "PUT records":
          if (RECORD_NAME.test(id)) return this.putRecord(me, id, request.headers.get("If-None-Match"), body);
          break;
        case "DELETE records":
          if (RECORD_NAME.test(id)) return this.deleteRecord(me, id);
          break;
        case "DELETE participants":
          if (id) return this.removeParticipant(me, id);
          break;
      }
    }
    if (id === "me") {
      if (route === "PUT participants" && rest.length === 1 && rest[0] === "name") return this.setName(me, body.data);
      const [kind, deviceId = ""] = rest;
      if (kind === "devices" && rest.length === 2 && DEVICE_ID.test(deviceId)) {
        if (route === "PUT participants") return this.putDevice(me, deviceId, body);
        if (route === "DELETE participants") return this.deleteDevice(me, deviceId);
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

  private async invite(me: Participant, body: Record<string, unknown>): Promise<Response> {
    if (!me.isOwner) return error(403, "forbidden");
    const purpose = body.purpose;
    if (purpose !== "invite" && purpose !== "migration") return error(400, "bad_request");
    const token = randomB64url(32);
    const hash = await sha256B64url(token);
    if (this.get("endedAt") !== null) return error(410, "ended");
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
    const body = await readObject(request);
    if (body instanceof Response) return body;
    const token = body.inviteToken;
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
    this.announce(participantId, "urgent");
    return Response.json({ participantId, participantSecret: secret }, { status: 201 });
  }

  // MARK: Deltagare

  private removeParticipant(me: Participant, id: string): Response {
    if (!me.isOwner && id !== me.id) return error(403, "forbidden");
    if (me.isOwner && id === me.id) return error(409, "owner_cannot_leave");
    const removed = this.ctx.storage.transactionSync(() => {
      const removed = this.sql.exec("UPDATE participants SET removedAt = ?, nameData = NULL WHERE id = ? AND removedAt IS NULL", now(), id).rowsWritten > 0;
      if (!removed) return false;
      this.sql.exec("DELETE FROM devices WHERE participantId = ?", id);
      this.bump();
      return true;
    });
    if (removed) {
      for (const socket of this.ctx.getWebSockets(id)) socket.close(4403, "removed");
      this.announce(me.id, "urgent");
    }
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
      this.sql.exec("DELETE FROM participants; DELETE FROM invites; DELETE FROM records; DELETE FROM deletions; DELETE FROM devices; DELETE FROM meta;");
      this.set("householdId", householdId);
      this.set("endedAt", now());
      this.set("endedReason", reason);
    });
    for (const socket of this.ctx.getWebSockets()) socket.close(4410, "ended");
  }

  private setName(me: Participant, data: unknown): Response {
    if (typeof data !== "string" || !BASE64URL.test(data)) return error(400, "bad_request");
    if (data.length > MAX_NAME) return error(413, "too_large");
    this.ctx.storage.transactionSync(() => {
      const changed = this.sql.exec("UPDATE participants SET nameData = ? WHERE id = ? AND removedAt IS NULL", data, me.id).rowsWritten > 0;
      if (changed) this.bump();
    });
    this.announce(me.id, null);
    return noContent();
  }

  // MARK: Enheter

  private putDevice(me: Participant, deviceId: string, body: Record<string, unknown>): Response {
    const { platform, token, environment, urgent = false } = body;
    if (typeof token !== "string" || typeof urgent !== "boolean") return error(400, "bad_request");
    const valid = platform === "apns"
      ? APNS_TOKEN.test(token) && (environment === "production" || environment === "sandbox")
      : platform === "fcm" && FCM_ID.test(token);
    if (!valid) return error(400, "bad_request");
    this.ctx.storage.transactionSync(() => {
      // Samma push-adress kan bara höra till en enhet, så att ingen får två push.
      this.sql.exec("DELETE FROM devices WHERE deviceId = ? OR token = ?", deviceId, token);
      this.sql.exec(
        "INSERT INTO devices(deviceId, participantId, platform, token, environment, urgent) VALUES (?, ?, ?, ?, ?, ?)",
        deviceId, me.id, platform as string, token, platform === "apns" ? (environment as string) : null, urgent ? 1 : 0,
      );
      this.sql.exec("DELETE FROM devices WHERE participantId = ?1 AND rowid NOT IN (SELECT rowid FROM devices WHERE participantId = ?1 ORDER BY rowid DESC LIMIT ?2)", me.id, MAX_DEVICES);
    });
    return noContent();
  }

  private deleteDevice(me: Participant, deviceId: string): Response {
    this.sql.exec("DELETE FROM devices WHERE deviceId = ? AND participantId = ?", deviceId, me.id);
    return noContent();
  }

  // MARK: Signaler och push

  private openSocket(me: Participant, request: Request): Response {
    if (request.headers.get("Upgrade") !== "websocket") return new Response(null, { status: 426 });
    const [client, server] = Object.values(new WebSocketPair()) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, [me.id]);
    return new Response(null, { status: 101, webSocket: client });
  }

  /** Appen skickar ingenting. Det som ändå kommer ignoreras. */
  override webSocketMessage(): void {}

  override webSocketError(): void {}

  /** Säger till öppna appar att något har ändrats, och skickar push till de andras enheter. */
  private announce(by: string | null, push: PushEvent | null): void {
    const seq = Number(this.get("seq"));
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(JSON.stringify({ seq }));
      } catch {
        // Uppkopplingen är på väg att stängas. Appen hämtar när den kopplar upp igen.
      }
    }
    if (push === null) return;
    const devices = this.sql.exec<DeviceRow>("SELECT deviceId, platform, token, environment, urgent FROM devices WHERE participantId IS NOT ?", by).toArray();
    if (devices.length === 0) return;
    const payload = { h: this.get("householdId")!, seq };
    this.ctx.waitUntil(Promise.all(devices.map(async (device) => {
      const result: PushResult = device.platform === "apns"
        ? await sendApns(this.env, device.token, device.environment ?? "production", payload)
        : await sendFcm(this.env, device.token, push === "urgent" && device.urgent === 1 ? "high" : "normal", payload);
      // Enheten kan ha fått ett nytt token medan push skickades.
      if (result === "invalid") this.sql.exec("DELETE FROM devices WHERE deviceId = ? AND token = ?", device.deviceId, device.token);
    })));
  }

  // MARK: Poster

  /** Den första skrivningen vinner, och en post skrivs aldrig över. */
  private putRecord(me: Participant, name: string, ifNoneMatch: string | null, body: Record<string, unknown>): Response {
    if (ifNoneMatch !== "*") return error(428, "precondition_required");
    const { kind, data } = body;
    const isMark = kind === "mark";
    if ((!isMark && kind !== "address") || typeof data !== "string" || !BASE64URL.test(data)) return error(400, "bad_request");
    if (data.length > MAX_DATA) return error(413, "too_large");
    const expires = body.expiresAt ?? null;
    if (isMark !== (typeof expires === "string")) return error(400, "bad_request");
    const expiresAt = typeof expires === "string" ? Date.parse(expires) : null;
    if (Number.isNaN(expiresAt)) return error(400, "bad_request");

    const existing = this.record(name);
    if (existing) return error(409, "conflict", { record: existing });
    if (this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM records").one().n >= MAX_RECORDS) return error(413, "too_large");
    this.ctx.storage.transactionSync(() => {
      this.sql.exec("DELETE FROM deletions WHERE name = ?", name);
      this.sql.exec(
        "INSERT INTO records(name, kind, data, by, at, expiresAt, seq) VALUES (?, ?, ?, ?, ?, ?, ?)",
        name, kind as string, data, me.id, now(), expiresAt === null ? null : new Date(expiresAt).toISOString(), this.bump(),
      );
    });
    this.announce(me.id, isMark ? "urgent" : null);
    return Response.json(this.record(name), { status: 201 });
  }

  private deleteRecord(me: Participant, name: string): Response {
    const kind = this.record(name)?.kind;
    if (kind === undefined) return noContent();
    this.ctx.storage.transactionSync(() => this.forget(name));
    this.announce(me.id, kind === "mark" ? "quiet" : null);
    return noContent();
  }

  /** Tar bort posten och minns det i 30 dagar, så att de andra får veta det. */
  private forget(name: string): void {
    this.sql.exec("DELETE FROM records WHERE name = ?", name);
    this.sql.exec("INSERT INTO deletions(name, seq, at) VALUES (?, ?, ?)", name, this.bump(), now());
  }

  private record(name: string): RecordRow | null {
    return this.sql.exec<RecordRow>("SELECT name, kind, data, by, at, expiresAt FROM records WHERE name = ?", name).toArray()[0] ?? null;
  }

  // MARK: Ändringar

  private changes(request: Request): Response {
    const text = new URL(request.url).searchParams.get("since") ?? "";
    if (!/^\d{1,15}$/.test(text)) return error(400, "bad_request");
    const since = Number(text);
    const seq = Number(this.get("seq"));
    // Ett löpnummer före den senaste rensade borttagningen, eller ett som servern inte har nått, ger allt.
    const full = since === 0 || since < Number(this.get("prunedSeq")) || since > seq;
    const from = full ? 0 : since;
    const participants = this.sql
      .exec<{ id: string; isOwner: number; joinedAt: string; nameData: string | null }>("SELECT id, isOwner, joinedAt, nameData FROM participants WHERE removedAt IS NULL ORDER BY rowid")
      .toArray()
      .map((row) => ({ id: row.id, isOwner: row.isOwner === 1, joinedAt: row.joinedAt, name: row.nameData }));
    const records = this.sql.exec<RecordRow>("SELECT name, kind, data, by, at, expiresAt FROM records WHERE seq > ? ORDER BY seq", from).toArray();
    const deleted = full ? [] : this.sql.exec<{ name: string }>("SELECT name FROM deletions WHERE seq > ? ORDER BY seq", from).toArray().map((row) => row.name);
    return Response.json({ seq, full, participants, records, deleted });
  }

  // MARK: Städning

  /** Bockar vars hämtdag har passerat, gamla borttagningar och ett hushåll som ingen använder. */
  override async alarm(): Promise<void> {
    if (!this.exists() || this.get("endedAt") !== null) return;
    if (Date.parse(this.get("lastActivity")!) + INACTIVE_LIFETIME <= Date.now()) {
      this.bury("inactive");
    } else {
      const before = this.get("seq");
      this.ctx.storage.transactionSync(() => {
        const expired = this.sql.exec<{ name: string }>("SELECT name FROM records WHERE expiresAt <= ?", now()).toArray();
        for (const { name } of expired) this.forget(name);
        const cutoff = new Date(Date.now() - DELETION_LIFETIME).toISOString();
        const pruned = this.sql.exec<{ seq: number | null }>("SELECT MAX(seq) AS seq FROM deletions WHERE at <= ?", cutoff).one().seq;
        if (pruned !== null) {
          this.sql.exec("DELETE FROM deletions WHERE at <= ?", cutoff);
          this.set("prunedSeq", String(Math.max(pruned, Number(this.get("prunedSeq")))));
        }
      });
      if (this.get("seq") !== before) this.announce(null, null);
    }
    await this.scheduleAlarm();
  }

  /** Sätter alarmet till nästa städning, om det inte redan står rätt. Ett avslutat hushåll har inget alarm. */
  private async scheduleAlarm(): Promise<void> {
    const current = await this.ctx.storage.getAlarm();
    if (this.get("endedAt") !== null) {
      if (current !== null) await this.ctx.storage.deleteAlarm();
      return;
    }
    const { expires, deleted } = this.sql
      .exec<{ expires: string | null; deleted: string | null }>("SELECT (SELECT MIN(expiresAt) FROM records) AS expires, (SELECT MIN(at) FROM deletions) AS deleted")
      .one();
    const next = Math.min(
      Date.parse(this.get("lastActivity")!) + INACTIVE_LIFETIME,
      expires === null ? Infinity : Date.parse(expires),
      deleted === null ? Infinity : Date.parse(deleted) + DELETION_LIFETIME,
    );
    if (current !== next) await this.ctx.storage.setAlarm(next);
  }

  /** Skrivs högst en gång om dagen, så att en hämtning oftast bara läser. */
  private noteActivity(): void {
    if (Date.now() - Date.parse(this.get("lastActivity")!) > DAY) this.set("lastActivity", now());
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
