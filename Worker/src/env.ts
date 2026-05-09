/// Type definitions for env bindings declared in wrangler.toml.

export interface Env {
  // vars
  ENV: "dev" | "prod";
  APPLE_TEAM_ID: string;
  APPLE_BUNDLE_ID: string;
  FREE_DAILY: string;
  DAILY_SPEND_USD_CAP: string;

  // secrets
  ANTHROPIC_API_KEY?: string;
  OPENAI_API_KEY?: string;
  REFERRAL_HMAC_SECRET?: string;
  DEV_BYPASS_SECRET?: string;
  /// Bearer token for /v1/admin/* read-only operational endpoints.
  /// Generated via: wrangler secret put ADMIN_TOKEN
  ADMIN_TOKEN?: string;

  // bindings
  NONCE: DurableObjectNamespace;
  RATE_LIMIT: DurableObjectNamespace;
  ENTITLEMENT: DurableObjectNamespace;
  KV: KVNamespace;
  /// Workers Analytics Engine dataset for per-guess token + spend events.
  /// Optional — guess flow degrades gracefully when missing.
  EVENTS?: AnalyticsEngineDataset;
}

export function freeDaily(env: Env): number {
  const n = parseInt(env.FREE_DAILY, 10);
  return Number.isFinite(n) && n > 0 ? n : 3;
}

export function dailySpendUsdCap(env: Env): number {
  const n = parseFloat(env.DAILY_SPEND_USD_CAP);
  return Number.isFinite(n) && n > 0 ? n : 5;
}
