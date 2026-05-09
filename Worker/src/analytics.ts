import type { Env } from "./env.js";

/// Per-guess event for the Cloudflare Workers Analytics Engine dataset.
/// Free tier: 25 M data points / month write, queryable via the SQL HTTP API
/// at https://api.cloudflare.com/client/v4/accounts/<account>/analytics_engine/sql.
///
/// Schema (read-side; column names in WAE are positional):
///   timestamp  (auto)
///   index1     keyId                                — used for sampling
///   blob1      keyId                                — text dimension
///   blob2      provider     ("anthropic" | "openai")
///   blob3      outcome      ("ok" | "error" | "refunded" | "paywall")
///   double1    input tokens
///   double2    output tokens
///   double3    usd cost     (6-decimal precision)
///   double4    latency ms
///
/// Sample queries (paste into the Cloudflare dashboard SQL UI):
///   -- USD spent in the last hour
///   SELECT SUM(double3) AS usd FROM ai_draw_events WHERE timestamp > NOW() - INTERVAL '1' HOUR
///
///   -- Per-provider call count + average latency, last 24h
///   SELECT blob2 AS provider, COUNT() AS calls, AVG(double4) AS avg_ms
///   FROM ai_draw_events WHERE timestamp > NOW() - INTERVAL '1' DAY GROUP BY blob2
///
///   -- Top 10 spenders today
///   SELECT blob1 AS keyId, SUM(double3) AS usd FROM ai_draw_events
///   WHERE timestamp > NOW() - INTERVAL '1' DAY
///   GROUP BY blob1 ORDER BY usd DESC LIMIT 10
export interface GuessEventRow {
  keyId: string;
  provider: "anthropic" | "openai";
  outcome: "ok" | "error" | "refunded" | "paywall";
  inputTokens: number;
  outputTokens: number;
  usd: number;
  latencyMs: number;
}

/// Write one row into the EVENTS dataset. Always best-effort: if the binding
/// is missing (e.g. running locally without WAE) or the runtime throws, the
/// guess flow is unaffected.
export function recordGuessEvent(env: Env, ev: GuessEventRow): void {
  const ds = env.EVENTS;
  if (!ds) return;
  try {
    ds.writeDataPoint({
      blobs: [ev.keyId, ev.provider, ev.outcome],
      doubles: [
        ev.inputTokens,
        ev.outputTokens,
        Math.round(ev.usd * 1_000_000) / 1_000_000,
        ev.latencyMs,
      ],
      indexes: [ev.keyId],
    });
  } catch {
    // analytics must never break a guess
  }
}
