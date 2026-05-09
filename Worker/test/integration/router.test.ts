import { describe, it, expect } from "vitest";
import { SELF } from "cloudflare:test";

/// Smoke + shape-lock tests that exercise the real router with real
/// Durable Objects and KV. Run with `npx vitest run -c vitest.workers.config.ts`.

describe("Worker router (integration)", () => {
  it("/v1/health returns ok", async () => {
    const r = await SELF.fetch("https://w/v1/health");
    expect(r.status).toBe(200);
    const j = await r.json();
    expect(j).toEqual({ ok: true });
  });

  it("/v1/admin/snapshot 401s without bearer", async () => {
    const r = await SELF.fetch("https://w/v1/admin/snapshot");
    expect(r.status).toBe(401);
  });

  it("/v1/admin/snapshot 401s with wrong bearer", async () => {
    const r = await SELF.fetch("https://w/v1/admin/snapshot", {
      headers: { authorization: "Bearer wrong" },
    });
    expect(r.status).toBe(401);
  });

  it("/v1/admin/snapshot 200s with right bearer and returns spend shape", async () => {
    const r = await SELF.fetch("https://w/v1/admin/snapshot", {
      headers: { authorization: "Bearer test-admin-token" },
    });
    expect(r.status).toBe(200);
    const j = (await r.json()) as {
      spend: { todayUsd: number; capUsd: number; remainingUsd: number; day: string };
      server: { env: string; now: string };
    };
    expect(j.spend).toBeDefined();
    expect(typeof j.spend.todayUsd).toBe("number");
    expect(typeof j.spend.capUsd).toBe("number");
    expect(j.spend.remainingUsd).toBeLessThanOrEqual(j.spend.capUsd);
    expect(j.server.env).toBe("dev");
  });

  it("unknown route 404s", async () => {
    const r = await SELF.fetch("https://w/v1/nope");
    expect(r.status).toBe(404);
  });

  it("/v1/nonce issues a nonce + value pair", async () => {
    const r = await SELF.fetch("https://w/v1/nonce", {
      method: "POST",
      body: JSON.stringify({ purpose: "assert" }),
      headers: { "content-type": "application/json" },
    });
    expect(r.status).toBe(200);
    const j = (await r.json()) as { nonceId: string; value: string; expiresAt: number };
    expect(typeof j.nonceId).toBe("string");
    expect(j.value).toMatch(/^[0-9a-f]{64}$/);
    expect(j.expiresAt).toBeGreaterThan(Date.now());
  });

  it("/v1/guess rejects extra top-level fields (zod strict)", async () => {
    const r = await SELF.fetch("https://w/v1/guess", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        v: 1,
        sessionId: "11111111-1111-1111-1111-111111111111",
        roundId:   "22222222-2222-2222-2222-222222222222",
        hintCategory: "cat",
        provider: "anthropic",
        imageBase64: btoa("\xFF\xD8\xFF" + "x".repeat(1024)),
        attestation: { keyId: "k", assertion: "a", nonceId: "n" },
        evil: "smuggled prompt",
      }),
    });
    // 400 from zod
    expect(r.status).toBe(400);
  });

  it("/v1/guess rejects unknown category", async () => {
    const r = await SELF.fetch("https://w/v1/guess", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        v: 1,
        sessionId: "11111111-1111-1111-1111-111111111111",
        roundId:   "22222222-2222-2222-2222-222222222222",
        hintCategory: "tank",
        provider: "anthropic",
        imageBase64: btoa("\xFF\xD8\xFF" + "x".repeat(1024)),
        attestation: { keyId: "k", assertion: "a", nonceId: "n" },
      }),
    });
    expect(r.status).toBe(400);
  });

  it("/v1/guess rejects non-image payload", async () => {
    const r = await SELF.fetch("https://w/v1/guess", {
      method: "POST",
      headers: { "content-type": "application/json", "x-dev-bypass": "wrong" },
      body: JSON.stringify({
        v: 1,
        sessionId: "11111111-1111-1111-1111-111111111111",
        roundId:   "22222222-2222-2222-2222-222222222222",
        hintCategory: "cat",
        provider: "anthropic",
        imageBase64: btoa("not an image"),
        attestation: { keyId: "k", assertion: "a", nonceId: "n" },
      }),
    });
    expect(r.status).toBe(400);
  });

  it("/v1/guess with bad dev-bypass HMAC is rejected as 401", async () => {
    const jpegBytes = new Uint8Array([0xff, 0xd8, 0xff, ...new Array(1024).fill(0x55)]);
    const b64 = btoa(String.fromCharCode(...jpegBytes));
    const r = await SELF.fetch("https://w/v1/guess", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-dev-bypass": "deadbeef",   // wrong HMAC
      },
      body: JSON.stringify({
        v: 1,
        sessionId: "11111111-1111-1111-1111-111111111111",
        roundId:   "22222222-2222-2222-2222-222222222222",
        hintCategory: "cat",
        provider: "anthropic",
        imageBase64: b64,
        // Valid-shape but bogus assertion/nonceId. Zod accepts; the
        // dev-bypass branch then rejects because the HMAC doesn't match.
        attestation: {
          keyId: "test-key-1",
          assertion: "AAAA",
          nonceId: "n-test",
        },
      }),
    });
    expect(r.status).toBe(401);
  });
});
