import { describe, it, expect, vi } from "vitest";
import { recordGuessEvent } from "../src/analytics.js";
import type { Env } from "../src/env.js";

/// recordGuessEvent must be best-effort: never throw, never block the guess
/// flow. These tests cover the three failure modes (missing binding, throwing
/// binding, well-formed binding).

function makeEnv(events?: AnalyticsEngineDataset): Env {
  return {
    ENV: "dev",
    APPLE_TEAM_ID: "T",
    APPLE_BUNDLE_ID: "com.x",
    FREE_DAILY: "3",
    DAILY_SPEND_USD_CAP: "5",
    NONCE: {} as any,
    RATE_LIMIT: {} as any,
    ENTITLEMENT: {} as any,
    KV: {} as any,
    EVENTS: events,
  } as Env;
}

describe("recordGuessEvent", () => {
  it("no-ops when EVENTS binding is absent", () => {
    expect(() =>
      recordGuessEvent(makeEnv(undefined), {
        keyId: "k1",
        provider: "anthropic",
        outcome: "ok",
        inputTokens: 100,
        outputTokens: 20,
        usd: 0.0005,
        latencyMs: 320,
      })
    ).not.toThrow();
  });

  it("swallows runtime errors from the dataset", () => {
    const events = {
      writeDataPoint: () => {
        throw new Error("boom");
      },
    } as unknown as AnalyticsEngineDataset;
    expect(() =>
      recordGuessEvent(makeEnv(events), {
        keyId: "k1",
        provider: "openai",
        outcome: "error",
        inputTokens: 0,
        outputTokens: 0,
        usd: 0,
        latencyMs: 100,
      })
    ).not.toThrow();
  });

  it("writes a row with the correct schema", () => {
    const writeDataPoint = vi.fn();
    const events = { writeDataPoint } as unknown as AnalyticsEngineDataset;
    recordGuessEvent(makeEnv(events), {
      keyId: "abc123",
      provider: "anthropic",
      outcome: "ok",
      inputTokens: 1024,
      outputTokens: 64,
      usd: 0.001234,
      latencyMs: 250,
    });
    expect(writeDataPoint).toHaveBeenCalledOnce();
    const row = writeDataPoint.mock.calls[0][0];
    expect(row.blobs).toEqual(["abc123", "anthropic", "ok"]);
    expect(row.doubles).toEqual([1024, 64, 0.001234, 250]);
    expect(row.indexes).toEqual(["abc123"]);
  });

  it("rounds usd to 6 decimals to keep dataset reasonable", () => {
    const writeDataPoint = vi.fn();
    const events = { writeDataPoint } as unknown as AnalyticsEngineDataset;
    recordGuessEvent(makeEnv(events), {
      keyId: "k",
      provider: "openai",
      outcome: "ok",
      inputTokens: 1,
      outputTokens: 1,
      usd: 0.0123456789,
      latencyMs: 1,
    });
    const row = writeDataPoint.mock.calls[0][0];
    // 0.0123456789 → 0.012346 after Math.round(usd * 1e6) / 1e6
    expect(row.doubles[2]).toBeCloseTo(0.012346, 6);
  });
});
