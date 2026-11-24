import { runDurableObjectAlarm, runInDurableObject, SELF } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { addMember, BASE, call, changes, createHousehold, stub, type Credentials } from "./support";

async function open(as: Credentials) {
  const response = await SELF.fetch(`${BASE}/households/${as.householdId}/socket`, {
    headers: { Upgrade: "websocket", Authorization: `Bearer ${as.participantId}.${as.participantSecret}` },
  });
  expect(response.status).toBe(101);
  const socket = response.webSocket!;
  const messages: unknown[] = [];
  let closed: number | null = null;
  socket.accept();
  socket.addEventListener("message", (event) => messages.push(JSON.parse(event.data as string)));
  socket.addEventListener("close", (event) => (closed = event.code));
  return { socket, messages, closed: () => closed };
}

const put = (as: Credentials) =>
  call("PUT", `/households/${as.householdId}/records/${"x".repeat(43)}`, { as, headers: { "If-None-Match": "*" }, body: { kind: "address", data: "AAAA" } });

describe("Signaler", () => {
  it("socketFarSeq", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const { messages } = await open(member);
    await put(owner);
    const { seq } = await changes(owner);
    await vi.waitFor(() => expect(messages).toEqual([{ seq }]));
    // Hibernation: uppkopplingen tillhör objektet och inte ett anrop.
    expect(await runInDurableObject(stub(owner.householdId), (_, s) => s.getWebSockets().length)).toBe(1);
  });

  it("allaAndringarSignaleras", async () => {
    const owner = await createHousehold();
    const { messages } = await open(owner);
    const member = await addMember(owner);
    await call("PUT", `/households/${owner.householdId}/participants/me/name`, { as: member, body: { data: "AAAA" } });
    await put(owner);
    await call("DELETE", `/households/${owner.householdId}/records/${"x".repeat(43)}`, { as: owner });
    await call("DELETE", `/households/${owner.householdId}/participants/${member.participantId}`, { as: member });
    await vi.waitFor(() => expect(messages).toHaveLength(5));
    expect(messages.at(-1)).toEqual({ seq: (await changes(owner)).seq });
  });

  it("stadningenSignaleras", async () => {
    const owner = await createHousehold();
    const { messages } = await open(owner);
    await call("PUT", `/households/${owner.householdId}/records/${"x".repeat(43)}`, {
      as: owner, headers: { "If-None-Match": "*" }, body: { kind: "mark", data: "AAAA", expiresAt: new Date(Date.now() - 1000).toISOString() },
    });
    await runDurableObjectAlarm(stub(owner.householdId));
    await vi.waitFor(() => expect(messages.at(-1)).toEqual({ seq: 3 }));
  });

  it("socketKraverDeltagare", async () => {
    const owner = await createHousehold();
    const other = await createHousehold();
    const path = `/households/${owner.householdId}/socket`;
    expect((await call("GET", path, { headers: { Upgrade: "websocket" } })).status).toBe(401);
    expect((await call("GET", path, { headers: { Upgrade: "websocket" }, as: { ...other, householdId: owner.householdId } })).status).toBe(401);
    expect((await call("GET", path, { as: owner })).status).toBe(426);
  });

  it("borttagenDeltagareKopplasNer", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const mine = await open(owner);
    const theirs = await open(member);
    await call("DELETE", `/households/${owner.householdId}/participants/${member.participantId}`, { as: owner });
    await vi.waitFor(() => expect(theirs.closed()).toBe(4403));
    expect(mine.closed()).toBeNull();
    await call("DELETE", `/households/${owner.householdId}`, { as: owner });
    await vi.waitFor(() => expect(mine.closed()).toBe(4410));
  });

  it("meddelandenFranAppenIgnoreras", async () => {
    const owner = await createHousehold();
    const { socket, messages } = await open(owner);
    socket.send("hej");
    await put(owner);
    await vi.waitFor(() => expect(messages).toHaveLength(1));
  });

  it("flyttenSlasPaMedVariabeln", async () => {
    const config = async (value: string) => (await worker.fetch(new Request(`${BASE}/config`) as never, { MIGRATION: value } as never)).json();
    expect(await config("on")).toEqual({ migration: true });
    expect(await config("off")).toEqual({ migration: false });
  });
});
