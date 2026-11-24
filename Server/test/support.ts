import { env, SELF } from "cloudflare:test";
import { inEU } from "../src/region";

export const BASE = "https://hushall.sopor.hardyson.se/v1";

export interface Credentials {
  householdId: string;
  participantId: string;
  participantSecret: string;
}

let nextIp = 0;

/** Ett anrop till brevlådan. Varje hushåll skapas från en egen IP-adress, om inget annat sägs. */
export function call(method: string, path: string, options: { as?: Credentials; body?: unknown; headers?: Record<string, string> } = {}): Promise<Response> {
  const headers: Record<string, string> = { ...options.headers };
  if (options.as) headers["Authorization"] = `Bearer ${options.as.participantId}.${options.as.participantSecret}`;
  if (options.body !== undefined) headers["Content-Type"] = "application/json";
  return SELF.fetch(`${BASE}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : typeof options.body === "string" ? options.body : JSON.stringify(options.body),
  });
}

export async function json<T = any>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export async function createHousehold(ip = `192.0.2.${nextIp++ % 250}-${nextIp}`): Promise<Credentials> {
  const response = await call("POST", "/households", { headers: { "CF-Connecting-IP": ip } });
  if (response.status !== 201) throw new Error(`Hushållet skapades inte: ${response.status}`);
  return json<Credentials>(response);
}

export async function invite(owner: Credentials, purpose = "invite"): Promise<string> {
  const response = await call("POST", `/households/${owner.householdId}/invites`, { as: owner, body: { purpose } });
  if (response.status !== 201) throw new Error(`Inbjudan skapades inte: ${response.status}`);
  return (await json<{ inviteToken: string }>(response)).inviteToken;
}

export function join(householdId: string, inviteToken: string): Promise<Response> {
  return call("POST", `/households/${householdId}/join`, { body: { inviteToken } });
}

export async function addMember(owner: Credentials): Promise<Credentials> {
  const response = await join(owner.householdId, await invite(owner));
  if (response.status !== 201) throw new Error(`Gick inte med: ${response.status}`);
  return { householdId: owner.householdId, ...(await json<{ participantId: string; participantSecret: string }>(response)) };
}

export function stub(householdId: string) {
  const namespace = inEU(env.HOUSEHOLD, env);
  return namespace.get(namespace.idFromName(householdId));
}

export async function changes(as: Credentials, since = 0) {
  return json(await call("GET", `/households/${as.householdId}/changes?since=${since}`, { as }));
}
