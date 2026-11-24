/** Felkoderna i protokollet. Bara `removed` och `ended` får ta bort hushållet i appen. */
export type ErrorCode =
  | "removed" | "ended" | "invite_invalid" | "full" | "conflict" | "not_found"
  | "unauthorized" | "forbidden" | "bad_request" | "too_many" | "too_large" | "precondition_required"
  | "owner_cannot_leave" | "migration_unavailable";

export function error(status: number, code: ErrorCode, extra: Record<string, unknown> = {}): Response {
  return Response.json({ error: code, ...extra }, { status });
}

export function noContent(): Response {
  return new Response(null, { status: 204 });
}

/** Kroppen som ett JSON-objekt, eller svaret när den inte är det eller är för stor. */
export async function readObject(request: Request): Promise<Record<string, unknown> | Response> {
  if (Number(request.headers.get("Content-Length") ?? 0) > MAX_BODY) return error(413, "too_large");
  const text = await request.text();
  if (text.length > MAX_BODY) return error(413, "too_large");
  try {
    const value: unknown = JSON.parse(text);
    return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : error(400, "bad_request");
  } catch {
    return error(400, "bad_request");
  }
}

/** Den största kroppen som läses, med marginal till den största posten. */
const MAX_BODY = 16 * 1024;
