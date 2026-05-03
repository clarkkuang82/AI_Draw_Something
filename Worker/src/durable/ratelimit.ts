import { DurableObject } from "cloudflare:workers";
import { utcDayKey } from "../util.js";

const REFILL_INTERVAL_MS = 3_000;     // 1 token / 3s
const BUCKET_CAPACITY = 20;
const DAILY_CAP = 200;

interface State {
  tokens: number;
  lastRefillAt: number;
  day: string;
  dayCount: number;
}

/// Per-keyId token bucket with a hard daily cap. One DO instance per attest
/// keyId — `RATE_LIMIT.idFromName(keyId)`.
export class RateLimitDO extends DurableObject {
  override async fetch(req: Request): Promise<Response> {
    const now = Date.now();
    const today = utcDayKey(now);
    let s = await this.ctx.storage.get<State>("s");
    if (!s) {
      s = { tokens: BUCKET_CAPACITY, lastRefillAt: now, day: today, dayCount: 0 };
    }

    if (s.day !== today) {
      s.day = today;
      s.dayCount = 0;
    }

    const elapsed = now - s.lastRefillAt;
    const refill = elapsed / REFILL_INTERVAL_MS;
    s.tokens = Math.min(BUCKET_CAPACITY, s.tokens + refill);
    s.lastRefillAt = now;

    if (s.dayCount >= DAILY_CAP) {
      await this.ctx.storage.put("s", s);
      return Response.json({ ok: false, reason: "daily" }, { status: 429 });
    }
    if (s.tokens < 1) {
      await this.ctx.storage.put("s", s);
      return Response.json({ ok: false, reason: "burst" }, { status: 429 });
    }
    s.tokens -= 1;
    s.dayCount += 1;
    await this.ctx.storage.put("s", s);
    return Response.json({ ok: true, remaining: Math.floor(s.tokens), dailyRemaining: DAILY_CAP - s.dayCount });
  }
}
