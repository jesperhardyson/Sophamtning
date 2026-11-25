import { runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { addMember, call, changes, createHousehold, invite, join, json, stub } from "./support";

const DAY = 24 * 60 * 60 * 1000;

afterEach(() => {
  vi.useRealTimers();
});

/** Flyttar klockan framåt utan att stoppa väntetider och löften. */
function advance(ms: number) {
  vi.useFakeTimers({ toFake: ["Date"], now: Date.now() + ms });
}

describe("Hushåll och deltagare", () => {
  it("skaparHushallMedAgare", async () => {
    const response = await call("POST", "/households", { headers: { "CF-Connecting-IP": "198.51.100.1" } });
    expect(response.status).toBe(201);
    const created = await json(response);
    expect(created.householdId).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(created.participantId).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(created.participantSecret).toMatch(/^[A-Za-z0-9_-]{43}$/);

    const body = await changes(created);
    expect(body.full).toBe(true);
    expect(body.records).toEqual([]);
    expect(body.deleted).toEqual([]);
    expect(body.participants).toEqual([{ id: created.participantId, isOwner: true, joinedAt: expect.any(String), name: null }]);
  });

  it("felHemlighetGer401", async () => {
    const owner = await createHousehold();
    const path = `/households/${owner.householdId}/changes?since=0`;
    const other = await createHousehold();
    for (const as of [{ ...owner, participantSecret: other.participantSecret }, { ...owner, participantId: other.participantId }]) {
      const response = await call("GET", path, { as });
      expect(response.status).toBe(401);
      expect(await json(response)).toEqual({ error: "unauthorized" });
    }
    expect((await call("GET", path)).status).toBe(401);
    expect((await call("GET", path, { headers: { Authorization: "Bearer fel" } })).status).toBe(401);
  });

  it("hemlighetenSparasBaraSomHash", async () => {
    const owner = await createHousehold();
    const token = await invite(owner);
    const stored = await runInDurableObject(stub(owner.householdId), (_, state) =>
      JSON.stringify([
        state.storage.sql.exec("SELECT * FROM participants").toArray(),
        state.storage.sql.exec("SELECT * FROM invites").toArray(),
        state.storage.sql.exec("SELECT * FROM meta").toArray(),
      ]),
    );
    expect(stored).toContain(owner.participantId);
    expect(stored).not.toContain(owner.participantSecret);
    expect(stored).not.toContain(token);
  });

  it("inbjudanGallerSjuDagar", async () => {
    const owner = await createHousehold();
    const response = await call("POST", `/households/${owner.householdId}/invites`, { as: owner, body: { purpose: "invite" } });
    expect(response.status).toBe(201);
    const { inviteToken, expiresAt } = await json(response);
    expect(Math.abs(Date.parse(expiresAt) - Date.now() - 7 * DAY)).toBeLessThan(5000);
    expect((await join(owner.householdId, inviteToken)).status).toBe(201);
    // Flera personer kan använda samma länk.
    expect((await join(owner.householdId, inviteToken)).status).toBe(201);

    advance(7 * DAY + 5000);
    const late = await join(owner.householdId, inviteToken);
    expect(late.status).toBe(404);
    expect(await json(late)).toEqual({ error: "invite_invalid" });
  });

  it("felInbjudanGerInviteInvalid", async () => {
    const owner = await createHousehold();
    const response = await join(owner.householdId, "A".repeat(43));
    expect(response.status).toBe(404);
    expect(await json(response)).toEqual({ error: "invite_invalid" });
  });

  it("baraAgarenBjuderIn", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const path = `/households/${owner.householdId}/invites`;
    const response = await call("POST", path, { as: member, body: { purpose: "invite" } });
    expect(response.status).toBe(403);
    expect(await json(response)).toEqual({ error: "forbidden" });
    expect((await call("DELETE", path, { as: member })).status).toBe(403);
    expect((await call("POST", path, { body: { purpose: "invite" } })).status).toBe(401);
  });

  it("okantSyfteGer400", async () => {
    const owner = await createHousehold();
    const path = `/households/${owner.householdId}/invites`;
    expect((await call("POST", path, { as: owner, body: { purpose: "annat" } })).status).toBe(400);
    expect((await call("POST", path, { as: owner, body: "inte json" })).status).toBe(400);
  });

  it("flyttinbjudanBaraEnGangOchInomEttDygn", async () => {
    const owner = await createHousehold();
    const path = `/households/${owner.householdId}/invites`;
    const response = await call("POST", path, { as: owner, body: { purpose: "migration" } });
    expect(response.status).toBe(201);
    expect(Math.abs(Date.parse((await json(response)).expiresAt) - Date.now() - 90 * DAY)).toBeLessThan(5000);
    expect((await call("POST", path, { as: owner, body: { purpose: "migration" } })).status).toBe(409);

    const late = await createHousehold();
    advance(DAY + 5000);
    expect((await call("POST", `/households/${late.householdId}/invites`, { as: late, body: { purpose: "migration" } })).status).toBe(409);
  });

  it("ogiltigforklaringRorInteFlytten", async () => {
    const owner = await createHousehold();
    const ordinary = await invite(owner);
    const migration = await invite(owner, "migration");
    expect((await call("DELETE", `/households/${owner.householdId}/invites`, { as: owner })).status).toBe(204);
    expect((await join(owner.householdId, ordinary)).status).toBe(404);
    expect((await join(owner.householdId, migration)).status).toBe(201);
  });

  it("elvaDeltagareGerFull", async () => {
    const owner = await createHousehold();
    const token = await invite(owner);
    let last = "";
    for (let i = 0; i < 9; i++) {
      const response = await join(owner.householdId, token);
      expect(response.status).toBe(201);
      last = (await json(response)).participantId;
    }
    const response = await join(owner.householdId, token);
    expect(response.status).toBe(409);
    expect(await json(response)).toEqual({ error: "full" });
    // Den som tas bort räknas inte längre.
    await call("DELETE", `/households/${owner.householdId}/participants/${last}`, { as: owner });
    expect((await join(owner.householdId, await invite(owner))).status).toBe(201);
  });

  it("borttagenDeltagareGerRemoved", async () => {
    const owner = await createHousehold();
    const [removed, leaving, other] = [await addMember(owner), await addMember(owner), await addMember(owner)];
    const path = (id: string) => `/households/${owner.householdId}/participants/${id}`;
    expect((await call("DELETE", path(removed.participantId), { as: other })).status).toBe(403);
    expect((await call("DELETE", path(removed.participantId), { as: owner })).status).toBe(204);
    expect((await call("DELETE", path(leaving.participantId), { as: leaving })).status).toBe(204);
    for (const as of [removed, leaving]) {
      const response = await call("GET", `/households/${owner.householdId}/changes?since=0`, { as });
      expect(response.status).toBe(403);
      expect(await json(response)).toEqual({ error: "removed" });
    }
    // Utan rätt hemlighet är det inget bevis för att personen har tagits bort.
    expect((await call("GET", `/households/${owner.householdId}/changes?since=0`, { as: { ...removed, participantSecret: other.participantSecret } })).status).toBe(401);
    const ids = (await changes(owner)).participants.map((p: { id: string }) => p.id);
    expect(ids).toEqual([owner.participantId, other.participantId]);
  });

  it("agarenKanInteLamna", async () => {
    const owner = await createHousehold();
    const response = await call("DELETE", `/households/${owner.householdId}/participants/${owner.participantId}`, { as: owner });
    expect(response.status).toBe(409);
    expect((await changes(owner)).participants).toHaveLength(1);
  });

  it("avslutatHushallGerEnded", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const token = await invite(owner);
    const path = `/households/${owner.householdId}`;
    expect((await call("DELETE", path, { as: member })).status).toBe(403);
    expect((await call("DELETE", path, { as: owner })).status).toBe(204);
    for (const as of [owner, member]) {
      const response = await call("GET", `${path}/changes?since=0`, { as });
      expect(response.status).toBe(410);
      expect(await json(response)).toEqual({ error: "ended" });
    }
    expect((await call("DELETE", path, { as: owner })).status).toBe(410);
    const late = await join(owner.householdId, token);
    expect(late.status).toBe(404);
    expect(await json(late)).toEqual({ error: "invite_invalid" });

    const left = await runInDurableObject(stub(owner.householdId), (_, state) => ({
      participants: state.storage.sql.exec("SELECT COUNT(*) AS n FROM participants").one().n,
      invites: state.storage.sql.exec("SELECT COUNT(*) AS n FROM invites").one().n,
      keys: state.storage.sql.exec("SELECT key FROM meta ORDER BY key").toArray().map((r) => r.key),
    }));
    expect(left).toEqual({ participants: 0, invites: 0, keys: ["endedAt", "endedReason", "householdId"] });
  });

  it("okantHushallGerNotFound", async () => {
    const owner = await createHousehold();
    const unknown = { ...owner, householdId: "A".repeat(22) };
    for (const response of [await call("GET", `/households/${unknown.householdId}/changes?since=0`, { as: unknown }), await join(unknown.householdId, "A".repeat(43))]) {
      expect(response.status).toBe(404);
      expect(await json(response)).toEqual({ error: "not_found" });
    }
    // Ett anrop mot ett slumpat id lagrar ingenting.
    const tables = await runInDurableObject(stub(unknown.householdId), (_, state) =>
      state.storage.sql.exec("SELECT name FROM sqlite_master WHERE name IN ('meta', 'participants')").toArray(),
    );
    expect(tables).toEqual([]);
  });

  it("okandSokvagGer404", async () => {
    const owner = await createHousehold();
    for (const path of ["/annat", `/households/${owner.householdId}/annat`, "/households/för-kort/changes", "/households/../config/x"]) {
      expect((await call("GET", path, { as: owner })).status).toBe(404);
    }
  });

  it("sexteHushalletFranSammaIpNekas", async () => {
    const ip = "203.0.113.7";
    for (let i = 0; i < 5; i++) await createHousehold(ip);
    const response = await call("POST", "/households", { headers: { "CF-Connecting-IP": ip } });
    expect(response.status).toBe(429);
    expect(await json(response)).toEqual({ error: "too_many" });
    await createHousehold("203.0.113.8");
    advance(60 * 60 * 1000 + 5000);
    await createHousehold(ip);
  });

  it("nyDeltagareOkarSeq", async () => {
    const owner = await createHousehold();
    const seq = (await changes(owner)).seq;
    await addMember(owner);
    expect((await changes(owner)).seq).toBe(seq + 1);
  });

  it("borttagningGorAllaInbjudningarOgiltiga", async () => {
    const owner = await createHousehold();
    const [removed, leaving] = [await addMember(owner), await addMember(owner)];
    const [ordinary, migration] = [await invite(owner), await invite(owner, "migration")];
    // Den som lämnar själv rör inga inbjudningar.
    await call("DELETE", `/households/${owner.householdId}/participants/${leaving.participantId}`, { as: leaving });
    expect((await join(owner.householdId, ordinary)).status).toBe(201);
    // Den som tas bort ska inte kunna gå med igen med en länk som redan är skickad.
    await call("DELETE", `/households/${owner.householdId}/participants/${removed.participantId}`, { as: owner });
    expect((await join(owner.householdId, ordinary)).status).toBe(404);
    expect((await join(owner.householdId, migration)).status).toBe(404);
    expect((await join(owner.householdId, await invite(owner))).status).toBe(201);
  });

  it("hogstTjugoInbjudningar", async () => {
    const owner = await createHousehold();
    const first = await invite(owner);
    for (let i = 0; i < 20; i++) await invite(owner);
    expect((await join(owner.householdId, first)).status).toBe(404);
    expect((await join(owner.householdId, await invite(owner))).status).toBe(201);
  });

  it("flyttinbjudanTrangsInteUtAvVanliga", async () => {
    const owner = await createHousehold();
    const migration = await invite(owner, "migration");
    for (let i = 0; i < 25; i++) await invite(owner);
    expect((await join(owner.householdId, migration)).status).toBe(201);
  });

  it("sammaIPv6NatRaknasSomEn", async () => {
    for (let i = 0; i < 5; i++) await createHousehold(`2001:db8:1:2::${i}`);
    const response = await call("POST", "/households", { headers: { "CF-Connecting-IP": "2001:0db8:0001:0002:ffff::1" } });
    expect(response.status).toBe(429);
    await createHousehold("2001:db8:1:3::1");
  });
});
