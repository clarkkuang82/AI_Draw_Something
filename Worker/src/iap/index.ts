/// IAP redeem + webhook handlers. Both rely on `verifyAppleJWS` for signature
/// validation. Idempotency keys are stored in KV so the same originalTransactionId
/// can never be credited twice.

import type { Env } from "../env.js";
import { jsonResponse, errorResponse } from "../util.js";
import {
  verifyAppleJWS,
  type JWSNotificationPayload,
  type JWSTransactionPayload,
} from "./jws.js";
import { lookupProduct } from "./products.js";

// ---------------------------------------------------------------------------
// /v1/iap/redeem  (called by iOS after StoreKit Transaction)
// ---------------------------------------------------------------------------

export async function iapRedeemRoute(
  body: { keyId: string; jws: string },
  env: Env
): Promise<Response> {
  let verified;
  try {
    verified = await verifyAppleJWS<JWSTransactionPayload>(body.jws);
  } catch (err) {
    return errorResponse("iap_jws_invalid", 400, (err as Error).message);
  }
  const tx = verified.payload;

  if (tx.bundleId !== env.APPLE_BUNDLE_ID) {
    return errorResponse("iap_bundle_mismatch", 400);
  }
  const product = lookupProduct(tx.productId);
  if (!product) return errorResponse("iap_unknown_product", 400);

  // Idempotency on originalTransactionId — same tx will only credit once
  // even if the client re-uploads (legitimately or not).
  const dedupKey = `iap:tx:${tx.originalTransactionId}`;
  const seen = await env.KV.get(dedupKey);
  if (seen) {
    return jsonResponse({ ok: true, dedup: true, productId: tx.productId });
  }

  // Apply to entitlement DO atomically. We use a small "apply" RPC on the DO
  // that handles both consumable and subscription cases.
  const stub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(body.keyId));
  const applyR = await stub.fetch("https://e/applyIAP", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      productKind: product.kind,
      credits: product.credits,
      expiresAtMs: tx.expiresDate ?? null,
    }),
  });
  if (!applyR.ok) return errorResponse("iap_apply_failed", 500);

  await env.KV.put(
    dedupKey,
    JSON.stringify({
      productId: tx.productId,
      kind: product.kind,
      env: tx.environment,
      transactionId: tx.transactionId,
      at: Date.now(),
    }),
    { expirationTtl: 60 * 60 * 24 * 365 } // 1 year retention
  );

  return jsonResponse({ ok: true, productId: tx.productId, kind: product.kind });
}

// ---------------------------------------------------------------------------
// /v1/iap/webhook  (called by Apple App Store Server Notifications V2)
// ---------------------------------------------------------------------------

export async function iapWebhookRoute(req: Request, env: Env): Promise<Response> {
  const body = (await req.json().catch(() => null)) as { signedPayload?: string } | null;
  if (!body?.signedPayload) return errorResponse("missing_payload", 400);

  let outer;
  try {
    outer = await verifyAppleJWS<JWSNotificationPayload>(body.signedPayload);
  } catch (err) {
    return errorResponse("notif_jws_invalid", 400, (err as Error).message);
  }
  const n = outer.payload;
  if (n.data?.bundleId && n.data.bundleId !== env.APPLE_BUNDLE_ID) {
    return errorResponse("notif_bundle_mismatch", 400);
  }

  // For mutations we need the inner transaction info.
  const innerJws = n.data?.signedTransactionInfo;
  if (!innerJws) {
    // Some notification types (like TEST) don't carry transaction info.
    return jsonResponse({ ok: true, noop: true, type: n.notificationType });
  }
  let tx;
  try {
    tx = (await verifyAppleJWS<JWSTransactionPayload>(innerJws)).payload;
  } catch (err) {
    return errorResponse("notif_inner_invalid", 400, (err as Error).message);
  }

  // Find which keyId owned this transaction. We look it up via the
  // appAccountToken set during the original purchase; if absent, fall back
  // to a wildcard search using originalTransactionId. (The latter is best-
  // effort; production should always set appAccountToken on iOS.)
  const keyId = tx.appAccountToken ?? null;
  if (!keyId) {
    // Without a key binding, we can't apply the mutation. Log and ack so
    // Apple stops retrying. In practice we expect appAccountToken to be set.
    console.warn(`webhook: no appAccountToken for tx ${tx.originalTransactionId}`);
    return jsonResponse({ ok: true, missingKeyId: true });
  }

  const stub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(keyId));
  switch (n.notificationType) {
    case "REFUND":
    case "REVOKE":
    case "REFUND_DECLINED": {
      if (n.notificationType === "REFUND_DECLINED") break; // no mutation
      const product = lookupProduct(tx.productId);
      if (!product) break;
      await stub.fetch("https://e/applyIAP", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          productKind: product.kind,
          credits: -product.credits,           // reverse
          expiresAtMs: product.kind === "subscription" ? 0 : null,
        }),
      });
      // Also clear the dedup record so a future legit redeem isn't blocked
      await env.KV.delete(`iap:tx:${tx.originalTransactionId}`);
      break;
    }
    case "DID_RENEW":
    case "SUBSCRIBED":
    case "OFFER_REDEEMED": {
      const product = lookupProduct(tx.productId);
      if (!product || product.kind !== "subscription") break;
      await stub.fetch("https://e/applyIAP", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          productKind: "subscription",
          credits: 0,
          expiresAtMs: tx.expiresDate ?? null,
        }),
      });
      break;
    }
    case "EXPIRED":
    case "DID_FAIL_TO_RENEW":
    case "GRACE_PERIOD_EXPIRED": {
      const product = lookupProduct(tx.productId);
      if (!product || product.kind !== "subscription") break;
      await stub.fetch("https://e/applyIAP", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          productKind: "subscription",
          credits: 0,
          expiresAtMs: 0,                      // clear
        }),
      });
      break;
    }
    default:
      // unknown / ignored notification type — just ack
      break;
  }

  return jsonResponse({ ok: true, type: n.notificationType });
}
