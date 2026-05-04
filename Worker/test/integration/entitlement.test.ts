import { describe, it, expect } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import type { EntitlementDO } from "../../src/durable/entitlement.js";

/// Direct DO exercises — bypass the HTTP layer to assert state transitions.
/// `runInDurableObject` runs the closure with the DO instance as `this`.

declare module "cloudflare:test" {
  interface ProvidedEnv {
    ENTITLEMENT: DurableObjectNamespace<EntitlementDO>;
  }
}

async function call(stub: DurableObjectStub<EntitlementDO>, path: string, body: any) {
  const r = await stub.fetch(`https://e${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
  return (await r.json()) as any;
}

describe("EntitlementDO", () => {
  it("debits free quota until exhausted then returns paywall", async () => {
    const id = env.ENTITLEMENT.idFromName("user-A");
    const stub = env.ENTITLEMENT.get(id);

    expect((await call(stub, "/debit", { freeDaily: 3 })).reason).toBe("free");
    expect((await call(stub, "/debit", { freeDaily: 3 })).reason).toBe("free");
    expect((await call(stub, "/debit", { freeDaily: 3 })).reason).toBe("free");
    const fourth = await call(stub, "/debit", { freeDaily: 3 });
    expect(fourth.ok).toBe(false);
    expect(fourth.reason).toBe("paywall");
  });

  it("paid credits are consumed before free quota and refundable", async () => {
    const id = env.ENTITLEMENT.idFromName("user-B");
    const stub = env.ENTITLEMENT.get(id);

    await call(stub, "/applyIAP", { productKind: "consumable", credits: 2 });
    expect((await call(stub, "/debit", { freeDaily: 3 })).reason).toBe("paid");
    expect((await call(stub, "/debit", { freeDaily: 3 })).reason).toBe("paid");
    expect((await call(stub, "/debit", { freeDaily: 3 })).reason).toBe("free");

    const refunded = await call(stub, "/refund", { reason: "paid" });
    expect(refunded.entitlement.paidCredits).toBe(1);
  });

  it("subscription bypasses both buckets and doesn't decrement", async () => {
    const id = env.ENTITLEMENT.idFromName("user-C");
    const stub = env.ENTITLEMENT.get(id);

    await call(stub, "/applyIAP", {
      productKind: "subscription",
      expiresAtMs: Date.now() + 86_400_000,
    });
    for (let i = 0; i < 5; i++) {
      const r = await call(stub, "/debit", { freeDaily: 3 });
      expect(r.ok).toBe(true);
      expect(r.reason).toBe("sub");
    }
    const after = await call(stub, "/get", {});
    expect(after.freeUsedToday).toBe(0);
    expect(after.paidCredits).toBe(0);
  });

  it("expired subscription falls back to free", async () => {
    const id = env.ENTITLEMENT.idFromName("user-D");
    const stub = env.ENTITLEMENT.get(id);
    await call(stub, "/applyIAP", {
      productKind: "subscription",
      expiresAtMs: Date.now() - 1,
    });
    const r = await call(stub, "/debit", { freeDaily: 3 });
    expect(r.reason).toBe("free");
  });

  it("REFUND-style negative credits never push paidCredits below zero", async () => {
    const id = env.ENTITLEMENT.idFromName("user-E");
    const stub = env.ENTITLEMENT.get(id);
    await call(stub, "/applyIAP", { productKind: "consumable", credits: 2 });
    await call(stub, "/applyIAP", { productKind: "consumable", credits: -100 });
    const e = await call(stub, "/get", {});
    expect(e.paidCredits).toBe(0);
  });

  it("recordSpend reports over=true when threshold breached", async () => {
    const id = env.ENTITLEMENT.idFromName("__global__");
    const stub = env.ENTITLEMENT.get(id);
    const r1 = await call(stub, "/recordSpend", { usd: 1.0, cap: 5 });
    expect(r1.over).toBe(false);
    const r2 = await call(stub, "/recordSpend", { usd: 5.0, cap: 5 });
    expect(r2.over).toBe(true);
  });

  it("markReferred is idempotent — second call rejects", async () => {
    const id = env.ENTITLEMENT.idFromName("user-F");
    const stub = env.ENTITLEMENT.get(id);
    const first = await call(stub, "/markReferred", { code: "ABC123", bonusCredits: 5 });
    expect(first.ok).toBe(true);
    const second = await call(stub, "/markReferred", { code: "DEF456", bonusCredits: 5 });
    expect(second.ok).toBe(false);
    expect(second.alreadyReferred).toBe(true);
  });

  it("awardReferral honours monthly cap", async () => {
    const id = env.ENTITLEMENT.idFromName("inviter-A");
    const stub = env.ENTITLEMENT.get(id);
    let lastCapped = false;
    for (let i = 0; i < 60; i++) {
      const r = await call(stub, "/awardReferral", { credits: 5, monthlyCap: 250 });
      lastCapped = lastCapped || r.capped === true;
    }
    expect(lastCapped).toBe(true);
  });

  // Direct DO entry — proves runInDurableObject is wired correctly.
  it("storage survives across calls (sanity)", async () => {
    const id = env.ENTITLEMENT.idFromName("user-G");
    const stub = env.ENTITLEMENT.get(id);
    await call(stub, "/applyIAP", { productKind: "consumable", credits: 7 });
    await runInDurableObject(stub, async (instance: any, state: DurableObjectState) => {
      const e = await state.storage.get<any>("e");
      expect(e?.paidCredits).toBe(7);
      void instance; // unused but typed
    });
  });
});
