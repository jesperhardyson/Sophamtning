import { DurableObject } from "cloudflare:workers";

const HOUR = 60 * 60 * 1000;
const LIMIT = 5;

/** Räknar nya hushåll från en IP-adress. Objektet nås med en hash av adressen och dagens datum, så adressen sparas aldrig. */
export class CreationLimiter extends DurableObject<Env> {
  /** Sant högst fem gånger i timmen. */
  async allow(): Promise<boolean> {
    const now = Date.now();
    const recent = ((await this.ctx.storage.get<number[]>("created")) ?? []).filter((at) => at > now - HOUR);
    if (recent.length >= LIMIT) return false;
    recent.push(now);
    await this.ctx.storage.put("created", recent);
    await this.ctx.storage.setAlarm(now + HOUR);
    return true;
  }

  override async alarm(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
