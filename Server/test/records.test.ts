import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { addMember, call, changes, createHousehold, json, stub, type Credentials } from "./support";

const DAY = 24 * 60 * 60 * 1000;

afterEach(() => {
  vi.useRealTimers();
});

function advance(ms: number) {
  vi.useFakeTimers({ toFake: ["Date"], now: Date.now() + ms });
}

/** Ett postnamn med rätt längd, 43 tecken base64url. */
const name = (n: number) => `post${n}`.padEnd(43, "x");
const inDays = (days: number) => new Date(Date.now() + days * DAY).toISOString();

function put(as: Credentials, n: number | string, body: Record<string, unknown> = {}, headers: Record<string, string> = { "If-None-Match": "*" }) {
  const id = typeof n === "number" ? name(n) : n;
  return call("PUT", `/households/${as.householdId}/records/${id}`, { as, headers, body: { kind: "address", data: "AAAA", ...body } });
}
const mark = (as: Credentials, n: number, days = 2) => put(as, n, { kind: "mark", expiresAt: inDays(days) });
const remove = (as: Credentials, n: number) => call("DELETE", `/households/${as.householdId}/records/${name(n)}`, { as });
const setName = (as: Credentials, data: unknown) => call("PUT", `/households/${as.householdId}/participants/me/name`, { as, body: { data } });

describe("Poster", () => {
  it("forstaSkrivningenVinner", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    expect((await put(owner, 1, { data: "AAAA" })).status).toBe(201);
    const second = await put(member, 1, { data: "BBBB" });
    expect(second.status).toBe(409);
    const body = await json(second);
    expect(body.error).toBe("conflict");
    expect(body.record).toEqual({ name: name(1), kind: "address", data: "AAAA", by: owner.participantId, at: expect.any(String), expiresAt: null });
    expect((await changes(member)).records).toEqual([body.record]);
  });

  it("putUtanIfNoneMatchGer428", async () => {
    const owner = await createHousehold();
    expect((await put(owner, 1, {}, {})).status).toBe(428);
    expect((await put(owner, 1, {}, { "If-None-Match": '"etag"' })).status).toBe(428);
  });

  it("bySattesAvServern", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await put(member, 1, { by: owner.participantId, at: "2020-01-01T00:00:00.000Z" });
    const record = (await changes(owner)).records[0];
    expect(record.by).toBe(member.participantId);
    expect(Math.abs(Date.parse(record.at) - Date.now())).toBeLessThan(5000);
  });

  it("ogiltigaPosterGer400", async () => {
    const owner = await createHousehold();
    const bad: Record<string, unknown>[] = [
      { kind: "annat" }, { data: "" }, { data: 1 }, { data: "inte base64url!" },
      { kind: "mark" }, { kind: "mark", expiresAt: "i morgon" }, { kind: "address", expiresAt: inDays(1) },
    ];
    for (const body of bad) expect((await put(owner, 1, body)).status, JSON.stringify(body)).toBe(400);
    expect((await put(owner, "kort")).status).toBe(404);
    expect((await changes(owner)).records).toEqual([]);
  });

  it("changesSinceGerBaraNytt", async () => {
    const owner = await createHousehold();
    await put(owner, 1);
    await put(owner, 2);
    const { seq } = await changes(owner);
    expect(await changes(owner, seq)).toMatchObject({ seq, full: false, records: [], deleted: [] });
    await put(owner, 3);
    await remove(owner, 1);
    const body = await changes(owner, seq);
    expect(body.full).toBe(false);
    expect(body.seq).toBe(seq + 2);
    expect(body.records.map((r: any) => r.name)).toEqual([name(3)]);
    expect(body.deleted).toEqual([name(1)]);
    expect(body.participants).toHaveLength(1);
    expect((await changes(owner)).records.map((r: any) => r.name)).toEqual([name(2), name(3)]);
  });

  it("postSomLaggsTillIgenArInteBorttagen", async () => {
    const owner = await createHousehold();
    await put(owner, 1);
    const { seq } = await changes(owner);
    await remove(owner, 1);
    await put(owner, 1, { data: "BBBB" });
    const body = await changes(owner, seq);
    expect(body.deleted).toEqual([]);
    expect(body.records.map((r: any) => r.data)).toEqual(["BBBB"]);
  });

  it("ogiltigSinceGer400OchFramtidaGerFull", async () => {
    const owner = await createHousehold();
    const path = (since: string) => call("GET", `/households/${owner.householdId}/changes${since}`, { as: owner });
    for (const since of ["?since=-1", "?since=x", "?since=1.5", ""]) expect((await path(since)).status, since).toBe(400);
    expect((await changes(owner, 9999)).full).toBe(true);
  });

  it("gammalSinceGerFull", async () => {
    const owner = await createHousehold();
    await put(owner, 1);
    const before = (await changes(owner)).seq;
    await remove(owner, 1);
    const after = (await changes(owner)).seq;
    advance(31 * DAY);
    await runDurableObjectAlarm(stub(owner.householdId));
    const left = await runInDurableObject(stub(owner.householdId), (_, state) => state.storage.sql.exec("SELECT COUNT(*) AS n FROM deletions").one().n);
    expect(left).toBe(0);
    expect((await changes(owner, before)).full).toBe(true);
    expect((await changes(owner, after)).full).toBe(false);
  });

  it("taBortSaknadPostGer204", async () => {
    const owner = await createHousehold();
    const { seq } = await changes(owner);
    expect((await remove(owner, 1)).status).toBe(204);
    expect((await changes(owner)).seq).toBe(seq);
  });

  it("allaKanTaBort", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await put(owner, 1);
    expect((await remove(member, 1)).status).toBe(204);
    expect((await changes(owner)).records).toEqual([]);
  });

  it("namnSyns", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const { seq } = await changes(owner);
    expect((await setName(member, "TmFtbg")).status).toBe(204);
    const body = await changes(owner, seq);
    expect(body.seq).toBe(seq + 1);
    expect(body.participants.map((p: any) => p.name)).toEqual([null, "TmFtbg"]);
    expect((await setName(member, "inte base64url!")).status).toBe(400);
  });

  it("bockRaderasEfterExpiresAt", async () => {
    const owner = await createHousehold();
    await mark(owner, 1, 1);
    await mark(owner, 2, 3);
    const { seq } = await changes(owner);
    advance(2 * DAY);
    expect(await runDurableObjectAlarm(stub(owner.householdId))).toBe(true);
    const body = await changes(owner, seq);
    expect(body.deleted).toEqual([name(1)]);
    expect(body.seq).toBeGreaterThan(seq);
    expect((await changes(owner)).records.map((r: any) => r.name)).toEqual([name(2)]);
  });

  it("grans200Poster", async () => {
    const owner = await createHousehold();
    for (let i = 0; i < 200; i++) expect((await put(owner, i)).status).toBe(201);
    const response = await put(owner, 200);
    expect(response.status).toBe(413);
    expect(await json(response)).toEqual({ error: "too_large" });
    // En post som redan finns är fortfarande en konflikt, och en borttagen ger plats.
    expect((await put(owner, 0)).status).toBe(409);
    await remove(owner, 0);
    expect((await put(owner, 200)).status).toBe(201);
  });

  it("grans8kB", async () => {
    const owner = await createHousehold();
    expect((await put(owner, 1, { data: "A".repeat(8192) })).status).toBe(201);
    expect((await put(owner, 2, { data: "A".repeat(8193) })).status).toBe(413);
    expect((await put(owner, 3, { data: "A".repeat(100_000) })).status).toBe(413);
  });

  it("grans512ByteNamn", async () => {
    const owner = await createHousehold();
    expect((await setName(owner, "A".repeat(512))).status).toBe(204);
    expect((await setName(owner, "A".repeat(513))).status).toBe(413);
  });

  it("hushallRaderasEfter400Dagar", async () => {
    const owner = await createHousehold();
    await put(owner, 1);
    advance(399 * DAY);
    await runDurableObjectAlarm(stub(owner.householdId));
    // Ett anrop börjar om räkningen.
    expect((await changes(owner)).records).toHaveLength(1);
    advance(399 * DAY);
    await runDurableObjectAlarm(stub(owner.householdId));
    advance(3 * DAY);
    await runDurableObjectAlarm(stub(owner.householdId));
    const response = await call("GET", `/households/${owner.householdId}/changes?since=0`, { as: owner });
    expect(response.status).toBe(410);
    const state = await runInDurableObject(stub(owner.householdId), (_, s) => ({
      reason: s.storage.sql.exec("SELECT value FROM meta WHERE key = 'endedReason'").one().value,
      records: s.storage.sql.exec("SELECT COUNT(*) AS n FROM records").one().n,
    }));
    expect(state).toEqual({ reason: "inactive", records: 0 });
    expect(await runDurableObjectAlarm(stub(owner.householdId))).toBe(false);
  });

  it("borttagenDeltagareRaknasInteSomAktivitet", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await call("DELETE", `/households/${owner.householdId}/participants/${member.participantId}`, { as: owner });
    advance(399 * DAY);
    await call("GET", `/households/${owner.householdId}/changes?since=0`, { as: member });
    advance(3 * DAY);
    await runDurableObjectAlarm(stub(owner.householdId));
    expect((await call("GET", `/households/${owner.householdId}/changes?since=0`, { as: owner })).status).toBe(410);
  });

  it("skrivningSamtidigtSomHushalletAvslutasLamnarIngetKvar", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await Promise.all([
      ...[1, 2, 3].map((n) => put(member, n)),
      setName(member, "TmFtbg"),
      call("DELETE", `/households/${owner.householdId}`, { as: owner }),
      ...[4, 5, 6].map((n) => put(member, n)),
    ]);
    const left = await runInDurableObject(stub(owner.householdId), (_, s) => ({
      records: s.storage.sql.exec("SELECT COUNT(*) AS n FROM records").one().n,
      keys: s.storage.sql.exec("SELECT key FROM meta ORDER BY key").toArray().map((row) => row.key),
    }));
    expect(left).toEqual({ records: 0, keys: ["endedAt", "endedReason", "householdId"] });
  });
});
