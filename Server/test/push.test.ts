import { env, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fromB64url } from "../src/encoding";
import { sendApns, sendFcm } from "../src/push";
import { addMember, call, changes, createHousehold, invite, join, stub, type Credentials } from "./support";

interface Sent {
  url: string;
  headers: Headers;
  body: any;
}

let sent: Sent[] = [];
let reply: (url: string) => Response;
const pushes = (): Sent[] => sent.filter((s) => !s.url.startsWith("https://oauth2."));

beforeEach(() => {
  sent = [];
  reply = () => new Response(null, { status: 200 });
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    const text = await request.text();
    sent.push({ url: request.url, headers: request.headers, body: text.startsWith("{") ? JSON.parse(text) : text });
    if (request.url.startsWith("https://oauth2.")) return Response.json({ access_token: "atkomst", expires_in: 3600 });
    return reply(request.url);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

const APNS = "ab".repeat(32);
const name = (n: number) => `post${n}`.padEnd(43, "x");
const tomorrow = () => new Date(Date.now() + 86_400_000).toISOString();

function device(as: Credentials, body: Record<string, unknown>, id = "enhet".padEnd(22, "x")) {
  return call("PUT", `/households/${as.householdId}/participants/me/devices/${id}`, { as, body });
}
const apns = (as: Credentials, token = APNS, id?: string) => device(as, { platform: "apns", token, environment: "production" }, id);
const fcm = (as: Credentials, urgent?: boolean, fid = "fidABCDEFGHIJKLMNOPQRS", id?: string) => device(as, { platform: "fcm", token: fid, ...(urgent === undefined ? {} : { urgent }) }, id ?? "android".padEnd(22, "x"));
const mark = (as: Credentials, n = 1) =>
  call("PUT", `/households/${as.householdId}/records/${name(n)}`, { as, headers: { "If-None-Match": "*" }, body: { kind: "mark", data: "AAAA", expiresAt: tomorrow() } });
const address = (as: Credentials, n = 1) =>
  call("PUT", `/households/${as.householdId}/records/${name(n)}`, { as, headers: { "If-None-Match": "*" }, body: { kind: "address", data: "AAAA" } });
const remove = (as: Credentials, n = 1) => call("DELETE", `/households/${as.householdId}/records/${name(n)}`, { as });
const wait = () => new Promise((resolve) => setTimeout(resolve, 30));
const devices = (as: Credentials) =>
  runInDurableObject(stub(as.householdId), (_, s) => s.storage.sql.exec("SELECT deviceId, participantId, platform, token, urgent FROM devices ORDER BY rowid").toArray());

describe("Push", () => {
  it("bockGerPushTillAndra", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    expect((await apns(owner, "cd".repeat(32), "agare".padEnd(22, "x"))).status).toBe(204);
    expect((await apns(member)).status).toBe(204);
    await mark(owner);
    await vi.waitFor(() => expect(pushes()).toHaveLength(1));
    await wait();
    expect(pushes()).toHaveLength(1);
    const [push] = pushes();
    expect(push!.url).toBe(`https://api.push.apple.com/3/device/${APNS}`);
    expect(push!.body).toEqual({ aps: { "content-available": 1 }, h: owner.householdId, seq: (await changes(owner)).seq });
    expect(push!.headers.get("apns-push-type")).toBe("background");
    expect(push!.headers.get("apns-priority")).toBe("5");
    expect(push!.headers.get("apns-topic")).toBe("se.hardyson.sophamtning");
  });

  it("sandboxFarSinEgenVard", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await device(member, { platform: "apns", token: APNS, environment: "sandbox" });
    await mark(owner);
    await vi.waitFor(() => expect(pushes()[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${APNS}`));
  });

  it("apnsSigneras", async () => {
    await sendApns(env as Env, APNS, "production", { h: "h", seq: 1 });
    const token = pushes()[0]!.headers.get("authorization")!.replace("bearer ", "");
    const [head, claims, signature] = token.split(".") as [string, string, string];
    expect(JSON.parse(atob(head))).toEqual({ alg: "ES256", kid: "ABC123DEFG" });
    expect(JSON.parse(new TextDecoder().decode(fromB64url(claims)))).toMatchObject({ iss: "TEAM123456" });
    const key = await crypto.subtle.importKey("jwk", JSON.parse((env as any).TEST_APNS_PUBLIC), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, fromB64url(signature), new TextEncoder().encode(`${head}.${claims}`))).toBe(true);
  });

  it("fcmSigneras", async () => {
    await sendFcm(env as Env, "fid", "normal", { h: "h", seq: 1 });
    await sendFcm(env as Env, "fid", "normal", { h: "h", seq: 2 });
    const exchanges = sent.filter((s) => s.url.startsWith("https://oauth2."));
    // Åtkomsttoken sparas, så bytet görs högst en gång.
    expect(exchanges.length).toBeLessThanOrEqual(1);
    if (exchanges[0]) {
      const assertion = new URLSearchParams(exchanges[0].body).get("assertion")!;
      const [head, claims, signature] = assertion.split(".") as [string, string, string];
      expect(JSON.parse(new TextDecoder().decode(fromB64url(claims)))).toMatchObject({
        iss: "push@prov.iam.gserviceaccount.com", aud: "https://oauth2.googleapis.com/token", scope: "https://www.googleapis.com/auth/firebase.messaging",
      });
      const key = await crypto.subtle.importKey("jwk", JSON.parse((env as any).TEST_FCM_PUBLIC), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
      expect(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, fromB64url(signature), new TextEncoder().encode(`${head}.${claims}`))).toBe(true);
    }
    expect(pushes()).toHaveLength(2);
    expect(pushes()[0]!.headers.get("authorization")).toBe("Bearer atkomst");
  });

  it("fcmSkickarBaraData", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await fcm(member);
    await mark(owner);
    await vi.waitFor(() => expect(pushes()).toHaveLength(1));
    expect(pushes()[0]!.url).toBe("https://fcm.googleapis.com/v1/projects/prov/messages:send");
    expect(pushes()[0]!.body).toEqual({
      message: {
        fid: "fidABCDEFGHIJKLMNOPQRS",
        data: { h: owner.householdId, seq: String((await changes(owner)).seq) },
        android: { priority: "normal", collapse_key: "hushall", ttl: "86400s" },
      },
    });
  });

  it("hogPrioritetBaraNarNotisenSyns", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const leaving = await addMember(owner);
    const token = await invite(owner);
    const priorities = async (act: () => Promise<unknown>) => {
      sent = [];
      await act();
      await vi.waitFor(() => expect(pushes().length).toBeGreaterThan(0));
      return pushes().map((p) => p.body.message.android.priority);
    };
    await fcm(member, true);
    expect(await priorities(() => mark(owner))).toEqual(["high"]);
    expect(await priorities(() => remove(owner))).toEqual(["normal"]);
    expect(await priorities(() => join(owner.householdId, token))).toEqual(["high"]);
    expect(await priorities(() => call("DELETE", `/households/${owner.householdId}/participants/${leaving.participantId}`, { as: leaving }))).toEqual(["high"]);
    await fcm(member, false);
    expect(await priorities(() => mark(owner, 2))).toEqual(["normal"]);
    await fcm(member);
    expect(await priorities(() => mark(owner, 3))).toEqual(["normal"]);
  });

  it("adressGerIngenPush", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await apns(member);
    await address(owner);
    await remove(owner);
    await call("PUT", `/households/${owner.householdId}/participants/me/name`, { as: owner, body: { data: "AAAA" } });
    await wait();
    expect(pushes()).toEqual([]);
  });

  it("borttagenDeltagareFarIngenPush", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await apns(member);
    await call("DELETE", `/households/${owner.householdId}/participants/${member.participantId}`, { as: owner });
    await mark(owner);
    await wait();
    expect(pushes()).toEqual([]);
    expect(await devices(owner)).toEqual([]);
  });

  it("ogiltigtTokenTasBort", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    const gone: [() => Promise<Response>, () => Response][] = [
      [() => apns(member), () => Response.json({ reason: "Unregistered" }, { status: 410 })],
      [() => apns(member), () => Response.json({ reason: "BadDeviceToken" }, { status: 400 })],
      [() => fcm(member), () => Response.json({ error: { details: [{ errorCode: "UNREGISTERED" }] } }, { status: 404 })],
    ];
    for (const [n, [register, answer]] of gone.entries()) {
      await register();
      expect(await devices(owner)).toHaveLength(1);
      reply = answer;
      await mark(owner, n);
      await vi.waitFor(async () => expect(await devices(owner)).toEqual([]));
    }
  });

  it("andraFelTarInteBortEnheten", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await apns(member);
    await fcm(member);
    const answers = [
      () => Response.json({ error: { details: [{ errorCode: "INVALID_ARGUMENT" }] }, reason: "BadMessageId" }, { status: 400 }),
      () => new Response("Not found", { status: 404 }),
      () => new Response(null, { status: 403 }),
      () => new Response(null, { status: 503 }),
    ];
    for (const [n, answer] of answers.entries()) {
      sent = [];
      reply = answer;
      await mark(owner, n);
      await vi.waitFor(() => expect(pushes()).toHaveLength(2));
      await wait();
      expect(await devices(owner)).toHaveLength(2);
    }
  });

  it("ettFelForEnEnhetStopparInteDeAndra", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await fcm(member);
    await apns(member);
    reply = (url) => {
      if (url.includes("fcm")) throw new Error("nätet");
      return new Response(null, { status: 200 });
    };
    expect((await mark(owner)).status).toBe(201);
    await vi.waitFor(() => expect(pushes()).toHaveLength(2));
    await wait();
    expect(await devices(owner)).toHaveLength(2);
  });

  it("nyttTokenUnderTidenTasInteBort", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await apns(member);
    let release: () => void = () => {};
    const held = new Promise<void>((resolve) => (release = resolve));
    vi.mocked(globalThis.fetch).mockImplementationOnce(async () => {
      await held;
      return new Response(null, { status: 410 });
    });
    await mark(owner);
    await wait();
    await apns(member, "ef".repeat(32));
    release();
    await wait();
    expect((await devices(owner)).map((d) => d.token)).toEqual(["ef".repeat(32)]);
  });

  it("taBortEnhetStopparPush", async () => {
    const owner = await createHousehold();
    const member = await addMember(owner);
    await apns(member);
    const path = `/households/${member.householdId}/participants/me/devices/${"enhet".padEnd(22, "x")}`;
    expect((await call("DELETE", path, { as: owner })).status).toBe(204);
    expect(await devices(owner)).toHaveLength(1);
    expect((await call("DELETE", path, { as: member })).status).toBe(204);
    await mark(owner);
    await wait();
    expect(pushes()).toEqual([]);
  });

  it("hogstFyraEnheterPerDeltagare", async () => {
    const owner = await createHousehold();
    for (let i = 0; i < 5; i++) await apns(owner, `${i}`.repeat(64), `enhet${i}`.padEnd(22, "x"));
    expect((await devices(owner)).map((d) => d.token)).toEqual([1, 2, 3, 4].map((i) => `${i}`.repeat(64)));
  });

  it("ogiltigEnhetGer400", async () => {
    const owner = await createHousehold();
    const bad: Record<string, unknown>[] = [
      { platform: "annat", token: APNS }, { platform: "apns", token: "../../x", environment: "production" }, { platform: "apns", token: APNS },
      { platform: "apns", token: APNS, environment: "annat" }, { platform: "fcm", token: "" }, { platform: "fcm", token: "a/b" }, { platform: "fcm", token: "fid", urgent: "ja" },
    ];
    for (const body of bad) expect((await device(owner, body)).status, JSON.stringify(body)).toBe(400);
    expect((await device(owner, { platform: "apns", token: APNS, environment: "production" }, "kort")).status).toBe(404);
    expect(await devices(owner)).toEqual([]);
  });

  it("utanHemligheterSkickasInget", async () => {
    expect(await sendApns({} as Env, APNS, "production", { h: "h", seq: 1 })).toBe("error");
    expect(await sendFcm({} as Env, "fid", "high", { h: "h", seq: 1 })).toBe("error");
    expect(sent).toEqual([]);
  });

  it("configFoljerVariabeln", async () => {
    const response = await call("GET", "/config");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ migration: false });
    expect((await call("POST", "/config")).status).toBe(404);
  });

  it("natfelBehallerApnsNyckeln", async () => {
    await sendApns(env as Env, APNS, "production", { h: "h", seq: 1 });
    reply = () => {
      throw new Error("nätet");
    };
    expect(await sendApns(env as Env, APNS, "production", { h: "h", seq: 2 })).toBe("error");
    reply = () => new Response(null, { status: 200 });
    await sendApns(env as Env, APNS, "production", { h: "h", seq: 3 });
    const tokens = pushes().map((p) => p.headers.get("authorization"));
    expect(new Set(tokens).size).toBe(1);
  });
});
