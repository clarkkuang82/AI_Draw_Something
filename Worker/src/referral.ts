/// Referral codes: deterministic per-keyId code derived via HMAC, stored in
/// EntitlementDO. Anti-abuse rules:
///   - one keyId can only consume one referral code (lifetime)
///   - inviter must have completed ≥ 1 game (we approximate: their entitlement
///     was loaded at least once, i.e. exists in storage)
///   - inviter's monthly referral credits are capped (see EntitlementDO)

import type { Env } from "./env.js";
import { errorResponse, hmacSHA256, jsonResponse } from "./util.js";

const REFERRAL_REWARD_CREDITS = 5;
const REFERRAL_MONTHLY_CAP = 250;
const CODE_LENGTH = 6;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // base32-ish, no easily-confused chars

export async function referralCodeFor(keyId: string, env: Env): Promise<string> {
  if (!env.REFERRAL_HMAC_SECRET) throw new Error("REFERRAL_HMAC_SECRET not set");
  const sig = await hmacSHA256(env.REFERRAL_HMAC_SECRET, keyId);
  let n = 0n;
  for (let i = 0; i < 8; i++) n = (n << 8n) | BigInt(sig[i]!);
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code = ALPHABET[Number(n % BigInt(ALPHABET.length))]! + code;
    n /= BigInt(ALPHABET.length);
  }
  return code;
}

// ---------------------------------------------------------------------------
// /v1/referral/code  → returns the caller's code (after attest verify)
// ---------------------------------------------------------------------------

export async function referralCodeRoute(keyId: string, env: Env): Promise<Response> {
  let code: string;
  try {
    code = await referralCodeFor(keyId, env);
  } catch (err) {
    return errorResponse("referral_unconfigured", 503, (err as Error).message);
  }
  // Cache the reverse lookup for redeem(). Do this opportunistically.
  await env.KV.put(`referral:code:${code}`, keyId, { expirationTtl: 60 * 60 * 24 * 365 });
  // Also store on the user's EntitlementDO.
  const stub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(keyId));
  await stub.fetch("https://e/setReferralCode", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ code }),
  });
  return jsonResponse({ code });
}

// ---------------------------------------------------------------------------
// /v1/referral/redeem  (called after attest verify)
// ---------------------------------------------------------------------------

export async function referralRedeemRoute(
  body: { keyId: string; code: string },
  env: Env
): Promise<Response> {
  const code = body.code.toUpperCase().trim();
  if (!/^[A-Z0-9]{4,12}$/.test(code)) return errorResponse("invalid_code", 400);

  const inviterKeyId = await env.KV.get(`referral:code:${code}`);
  if (!inviterKeyId) return errorResponse("code_unknown", 404);
  if (inviterKeyId === body.keyId) return errorResponse("self_redeem", 400);

  // Mark redeemer as referred + credit bonus
  const redeemerStub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(body.keyId));
  const markR = await redeemerStub.fetch("https://e/markReferred", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ code, bonusCredits: REFERRAL_REWARD_CREDITS }),
  });
  const markJ = (await markR.json()) as { ok: boolean; alreadyReferred: boolean };
  if (!markJ.ok && markJ.alreadyReferred) {
    return errorResponse("already_referred", 409);
  }

  // Award the inviter immediately (simpler MVP than the deferred-on-first-game
  // design). Capped per-month inside the DO.
  const inviterStub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(inviterKeyId));
  const awardR = await inviterStub.fetch("https://e/awardReferral", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      credits: REFERRAL_REWARD_CREDITS,
      monthlyCap: REFERRAL_MONTHLY_CAP,
    }),
  });
  const awardJ = (await awardR.json()) as { ok: boolean; capped: boolean };
  return jsonResponse({
    ok: true,
    bonusCreditsToYou: REFERRAL_REWARD_CREDITS,
    inviterAwarded: awardJ.ok,
    inviterCapped: awardJ.capped,
  });
}
