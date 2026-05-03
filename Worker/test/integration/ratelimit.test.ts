import { describe, it, expect } from "vitest";
import { env } from "cloudflare:test";
import type { RateLimitDO } from "../../src/durable/ratelimit.js";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    RATE_LIMIT: DurableObjectNamespace<RateLimitDO>;
  }
}

async function bump(stub: DurableObjectStub<RateLimitDO>) {
  const r = await stub.fetch("https://rl/", { method: "POST" });
  const j = (await r.json()) as { ok: boolean; reason?: string };
  return { status: r.status, ...j };
}

describe("RateLimitDO", () => {
  it("allows up to bucket capacity in a burst, then 429s with reason=burst", async () => {
    const id = env.RATE_LIMIT.idFromName("dev-burst");
    const stub = env.RATE_LIMIT.get(id);

    let allowedCount = 0;
    let burstHit = false;
    for (let i = 0; i < 30; i++) {
      const r = await bump(stub);
      if (r.ok) allowedCount += 1;
      else if (r.reason === "burst") { burstHit = true; break; }
    }
    expect(allowedCount).toBeGreaterThan(0);
    expect(burstHit).toBe(true);
  });

  it("isolates state per keyId (different DO instances)", async () => {
    const a = env.RATE_LIMIT.get(env.RATE_LIMIT.idFromName("user-X"));
    const b = env.RATE_LIMIT.get(env.RATE_LIMIT.idFromName("user-Y"));
    const r1 = await bump(a);
    const r2 = await bump(b);
    expect(r1.ok).toBe(true);
    expect(r2.ok).toBe(true);
  });
});
