import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

/// Separate config — we keep the fast Node-pool unit tests as the default
/// (`npm test`) and run integration tests in the Workers pool when needed.
/// Run via `npx vitest run -c vitest.workers.config.ts`.
export default defineWorkersConfig({
  test: {
    include: ["test/integration/**/*.test.ts"],
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          // Fill in test-only secrets so attestation/spend logic doesn't
          // explode on undefined.
          bindings: {
            ENV: "dev",
            APPLE_TEAM_ID: "TESTTEAMID",
            APPLE_BUNDLE_ID: "com.example.aidraw",
            FREE_DAILY: "3",
            DAILY_SPEND_USD_CAP: "5",
            DEV_BYPASS_SECRET: "test-bypass-secret",
            REFERRAL_HMAC_SECRET: "test-referral-secret",
          },
        },
      },
    },
  },
});
