import { b64url, fromB64url } from "./encoding";

export interface PushPayload {
  h: string;
  seq: number;
}

/** `invalid` betyder att enheten inte längre finns hos tjänsten, och då glöms den. */
export type PushResult = "ok" | "invalid" | "error";

const TOPIC = "se.hardyson.sophamtning";
const APNS_HOST = { production: "api.push.apple.com", sandbox: "api.sandbox.push.apple.com" };
/** APNs godtar en token i högst en timme. */
const APNS_TOKEN_LIFETIME = 50 * 60 * 1000;
const OAUTH_URL = "https://oauth2.googleapis.com/token";

// MARK: APNs

let apnsToken: { keyId: string; value: Promise<string>; expires: number } | null = null;

/** En tyst push till en iPhone. Den bär bara hushållets id och löpnumret. */
export async function sendApns(env: Env, token: string, environment: "production" | "sandbox", payload: PushPayload): Promise<PushResult> {
  const { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID } = env;
  if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) return "error";
  try {
    if (!apnsToken || apnsToken.keyId !== APNS_KEY_ID || apnsToken.expires <= Date.now()) {
      apnsToken = { keyId: APNS_KEY_ID, value: signApns(APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID), expires: Date.now() + APNS_TOKEN_LIFETIME };
    }
    const response = await fetch(`https://${APNS_HOST[environment]}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await apnsToken.value}`,
        "apns-push-type": "background",
        "apns-priority": "5",
        "apns-topic": TOPIC,
      },
      body: JSON.stringify({ aps: { "content-available": 1 }, ...payload }),
    });
    if (response.ok) return "ok";
    const reason = await field(response, (body) => body.reason);
    if (response.status === 410 || (response.status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"))) return "invalid";
    // En nekad token görs om nästa gång.
    if (response.status === 403) apnsToken = null;
    console.warn(`APNs svarade ${response.status} ${reason ?? ""}`);
  } catch (e) {
    apnsToken = null;
    console.warn(`APNs kunde inte nås: ${e instanceof Error ? e.message : "okänt fel"}`);
  }
  return "error";
}

async function signApns(key: string, keyId: string, teamId: string): Promise<string> {
  const algorithm = { name: "ECDSA", namedCurve: "P-256" };
  const imported = await crypto.subtle.importKey("pkcs8", pemBytes(key), algorithm, false, ["sign"]);
  const unsigned = `${part({ alg: "ES256", kid: keyId })}.${part({ iss: teamId, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, imported, new TextEncoder().encode(unsigned));
  return `${unsigned}.${b64url(new Uint8Array(signature))}`;
}

// MARK: FCM

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let fcmToken: { email: string; value: Promise<{ token: string; expires: number }> } | null = null;

/** En push med bara data till en Android-telefon. Hög prioritet används bara när appen visar en notis för den. */
export async function sendFcm(env: Env, fid: string, priority: "high" | "normal", payload: PushPayload): Promise<PushResult> {
  if (!env.FCM_SERVICE_ACCOUNT) return "error";
  try {
    const account = JSON.parse(env.FCM_SERVICE_ACCOUNT) as ServiceAccount;
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${await accessToken(account)}`, "content-type": "application/json" },
      body: JSON.stringify({
        message: {
          fid,
          data: { h: payload.h, seq: String(payload.seq) },
          android: { priority, collapse_key: "hushall", ttl: "86400s" },
        },
      }),
    });
    if (response.ok) return "ok";
    const code = await field(response, (body) => body.error?.details?.find((d: any) => typeof d.errorCode === "string")?.errorCode);
    if (response.status === 404 && code === "UNREGISTERED") return "invalid";
    if (response.status === 401) fcmToken = null;
    console.warn(`FCM svarade ${response.status} ${code ?? ""}`);
  } catch (e) {
    console.warn(`FCM kunde inte nås: ${e instanceof Error ? e.message : "okänt fel"}`);
  }
  return "error";
}

/** Åtkomsttoken hos Google, som sparas i minnet tills den har gått ut. Två push samtidigt delar på ett byte. */
async function accessToken(account: ServiceAccount): Promise<string> {
  const cached = fcmToken;
  if (cached?.email === account.client_email) {
    const current = await cached.value.catch(() => null);
    if (current && current.expires > Date.now()) return current.token;
    if (fcmToken === cached) fcmToken = null;
  }
  fcmToken ??= { email: account.client_email, value: exchange(account) };
  return (await fcmToken.value).token;
}

async function exchange(account: ServiceAccount): Promise<{ token: string; expires: number }> {
  const algorithm = { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
  const key = await crypto.subtle.importKey("pkcs8", pemBytes(account.private_key), algorithm, false, ["sign"]);
  const issued = Math.floor(Date.now() / 1000);
  const claims = { iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: OAUTH_URL, iat: issued, exp: issued + 3600 };
  const unsigned = `${part({ alg: "RS256", typ: "JWT" })}.${part(claims)}`;
  const signature = await crypto.subtle.sign(algorithm.name, key, new TextEncoder().encode(unsigned));
  const response = await fetch(OAUTH_URL, {
    method: "POST",
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${b64url(new Uint8Array(signature))}` }),
  });
  if (!response.ok) throw new Error(`OAuth svarade ${response.status}`);
  const body = (await response.json()) as { access_token: string; expires_in: number };
  return { token: body.access_token, expires: Date.now() + (body.expires_in - 60) * 1000 };
}

// MARK: Gemensamt

function part(value: object): string {
  return b64url(new TextEncoder().encode(JSON.stringify(value)));
}

function pemBytes(pem: string): Uint8Array {
  return fromB64url(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "").replaceAll("=", ""));
}

async function field(response: Response, pick: (body: any) => unknown): Promise<string | null> {
  try {
    const value = pick(await response.json());
    return typeof value === "string" ? value : null;
  } catch {
    return null;
  }
}
