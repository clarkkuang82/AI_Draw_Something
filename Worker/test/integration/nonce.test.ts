import { describe, it, expect } from "vitest";
import { env } from "cloudflare:test";
import type { NonceDO } from "../../src/durable/nonce.js";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    NONCE: DurableObjectNamespace<NonceDO>;
  }
}

async function issue(stub: DurableObjectStub<NonceDO>, purpose: "attest" | "assert") {
  const r = await stub.fetch("https://nonce/issue", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ purpose }),
  });
  return (await r.json()) as { id: string; value: string; expiresAt: number };
}

async function consume(stub: DurableObjectStub<NonceDO>, id: string, purpose: "attest" | "assert") {
  const r = await stub.fetch("https://nonce/consume", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id, purpose }),
  });
  return { status: r.status, ...((await r.json()) as { ok: boolean; reason?: string; value?: string }) };
}

describe("NonceDO", () => {
  it("issued nonce can be consumed exactly once", async () => {
    const stub = env.NONCE.get(env.NONCE.idFromName("nonce-test-1"));
    const issued = await issue(stub, "assert");
    expect(issued.value).toMatch(/^[0-9a-f]{64}$/);

    const first = await consume(stub, issued.id, "assert");
    expect(first.ok).toBe(true);
    expect(first.value).toBe(issued.value);

    const second = await consume(stub, issued.id, "assert");
    expect(second.ok).toBe(false);
    expect(second.reason).toBe("consumed");
  });

  it("rejects purpose mismatch", async () => {
    const stub = env.NONCE.get(env.NONCE.idFromName("nonce-test-2"));
    const issued = await issue(stub, "attest");
    const r = await consume(stub, issued.id, "assert");
    expect(r.ok).toBe(false);
    expect(r.reason).toBe("purpose");
  });

  it("404s on unknown id", async () => {
    const stub = env.NONCE.get(env.NONCE.idFromName("nonce-test-3"));
    const r = await consume(stub, "non-existent-id", "assert");
    expect(r.ok).toBe(false);
    expect(r.reason).toBe("missing");
  });
});
