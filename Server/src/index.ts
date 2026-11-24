import { randomB64url, sha256B64url } from "./encoding";
import { inEU } from "./region";
import { error } from "./responses";

export { Household } from "./household";
export { CreationLimiter } from "./limiter";

const ID = /^[A-Za-z0-9_-]{22}$/;

export default {
  async fetch(request, env): Promise<Response> {
    const [, version, collection = "", householdId = ""] = new URL(request.url).pathname.split("/");
    if (version === "v1" && collection === "config" && !householdId && request.method === "GET") {
      return Response.json({ migration: (env.MIGRATION as string) === "on" });
    }
    if (version !== "v1" || collection !== "households") return error(404, "not_found");
    if (!householdId) return request.method === "POST" ? createHousehold(request, env) : error(404, "not_found");
    if (!ID.test(householdId)) return error(404, "not_found");
    return household(env, householdId).fetch(request);
  },
} satisfies ExportedHandler<Env>;

/** Hushållets objekt, som alltid ligger i EU. */
function household(env: Env, householdId: string) {
  const namespace = inEU(env.HOUSEHOLD, env);
  return namespace.get(namespace.idFromName(householdId));
}

async function createHousehold(request: Request, env: Env): Promise<Response> {
  const limiters = inEU(env.LIMITER, env);
  const ip = request.headers.get("CF-Connecting-IP") ?? "okänd";
  const limiter = limiters.get(limiters.idFromName(await sha256B64url(`${ip}.${new Date().toISOString().slice(0, 10)}`)));
  if (!(await limiter.allow())) return error(429, "too_many");
  const householdId = randomB64url(16);
  const owner = await household(env, householdId).create(householdId);
  return Response.json({ householdId, ...owner }, { status: 201 });
}
