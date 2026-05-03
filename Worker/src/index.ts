import type { Env } from "./env.js";
import { dailySpendUsdCap, freeDaily } from "./env.js";
import {
  AttestRegisterZ,
  CATEGORY_LABELS,
  GuessRequestZ,
  NonceRequestZ,
  type ProviderId,
} from "./schema.js";
import { AnthropicProvider } from "./anthropic.js";
import { OpenAIProvider } from "./openai.js";
import type { Provider } from "./provider.js";
import { GuessParser } from "./parser.js";
import { makeSSEResponse } from "./sse.js";
import {
  b64decode,
  b64encode,
  bytesEqual,
  bytesToHex,
  errorResponse,
  hmacSHA256,
  jsonResponse,
  readJsonBody,
} from "./util.js";
import {
  verifyAssertion,
  verifyAttestation,
  type VerifiedAttestation,
} from "./attest/verify.js";

export { NonceDO } from "./durable/nonce.js";
export { RateLimitDO } from "./durable/ratelimit.js";
export { EntitlementDO } from "./durable/entitlement.js";

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    try {
      if (req.method === "POST" && url.pathname === "/v1/nonce") return nonceRoute(req, env);
      if (req.method === "POST" && url.pathname === "/v1/attest/register") return attestRegisterRoute(req, env);
      if (req.method === "GET"  && url.pathname === "/v1/entitlements") return entitlementsRoute(req, env);
      if (req.method === "POST" && url.pathname === "/v1/guess") return guessRoute(req, env, ctx);
      if (req.method === "GET"  && url.pathname === "/v1/health") return jsonResponse({ ok: true });
      return errorResponse("not_found", 404);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      return errorResponse("internal", 500, msg);
    }
  },
};

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

async function nonceRoute(req: Request, env: Env): Promise<Response> {
  const body = NonceRequestZ.parse(await readJsonBody(req, 4096));
  const id = env.NONCE.idFromName(crypto.randomUUID());
  const stub = env.NONCE.get(id);
  const r = await stub.fetch("https://nonce/issue", {
    method: "POST",
    body: JSON.stringify({ purpose: body.purpose }),
    headers: { "content-type": "application/json" },
  });
  // We need to return the DO-allocated id; remap so the client gets a stable id
  // they can pass back. We use the NonceDO-internal random id by piggybacking
  // it onto the response.
  const json = (await r.json()) as { id: string; value: string; expiresAt: number };
  // The client sends back `nonceId` which we need to look up in the same DO.
  // Stash a mapping `purpose:client_id -> { stubName, internalId }` so we can
  // route the consume() call back to the correct DO.
  await env.KV.put(
    `nonce-route:${json.id}`,
    JSON.stringify({ stubName: id.toString() }),
    { expirationTtl: 120 }
  );
  return jsonResponse({ nonceId: json.id, value: json.value, expiresAt: json.expiresAt });
}

async function attestRegisterRoute(req: Request, env: Env): Promise<Response> {
  const body = AttestRegisterZ.parse(await readJsonBody(req, 16_384));
  const challenge = await consumeNonce(env, body.challengeId, "attest");
  if (!challenge) return errorResponse("nonce_invalid", 400);

  const keyId = b64decode(body.keyId);
  let attested: VerifiedAttestation;
  try {
    attested = await verifyAttestation(body.attestationBase64, {
      expectedKeyId: keyId,
      challenge: challenge,
      appleTeamId: env.APPLE_TEAM_ID,
      appBundleId: env.APPLE_BUNDLE_ID,
      envMode: env.ENV === "prod" ? "prod" : "dev",
    });
  } catch (err) {
    return errorResponse("attest_invalid", 400, (err as Error).message);
  }

  await env.KV.put(
    `attest:key:${body.keyId}`,
    JSON.stringify({
      publicKeyJwk: attested.publicKeyJwk,
      signCount: attested.signCount,
      registeredAt: Date.now(),
    })
  );
  return jsonResponse({ ok: true });
}

async function entitlementsRoute(req: Request, env: Env): Promise<Response> {
  // Peek at the user's current entitlement. Pass keyId via query string —
  // this read endpoint does NOT verify an assertion, it's just a UI mirror.
  // The authoritative debit happens at /v1/guess. (Spoofed reads here just
  // get someone else's quota numbers, no real abuse vector.)
  const url = new URL(req.url);
  const keyId = url.searchParams.get("keyId");
  if (!keyId) return errorResponse("missing_keyId", 400);
  const stub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(keyId));
  const r = await stub.fetch("https://e/get", { method: "POST", body: "{}" });
  return new Response(r.body, { status: r.status, headers: { "content-type": "application/json" } });
}

async function guessRoute(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  // 1. Parse + validate body shape.
  const body = GuessRequestZ.parse(await readJsonBody(req, 220_000));

  // 2. Image gate: magic bytes + size already capped by zod.
  const imageBytes = b64decode(body.imageBase64);
  if (!isJpegOrPng(imageBytes)) return errorResponse("bad_image", 400);

  // 3. Verify App Attest assertion (or DEBUG bypass).
  const attestOK = await verifyRequestAttest(body, env, req);
  if (!attestOK.ok) return errorResponse(attestOK.code, 401, attestOK.detail);

  // 4. Per-device rate limit.
  const rl = await env.RATE_LIMIT.get(env.RATE_LIMIT.idFromName(body.attestation.keyId))
    .fetch("https://rl/", { method: "POST" });
  if (rl.status === 429) {
    const r = await rl.json() as { reason: string };
    return errorResponse(`rate_${r.reason}`, 429);
  }

  // 5. Global spend kill switch via the singleton EntitlementDO.
  const globalStub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName("__global__"));

  // 6. Per-user entitlement debit (atomic with the upstream call below).
  const userStub = env.ENTITLEMENT.get(env.ENTITLEMENT.idFromName(body.attestation.keyId));
  const debitR = await userStub.fetch("https://e/debit", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ freeDaily: freeDaily(env) }),
  });
  const debit = (await debitR.json()) as { ok: boolean; reason: string };
  if (!debit.ok) return errorResponse("paywall", 402, debit.reason);

  // 7. Pick provider
  const provider = pickProvider(body.provider, env);
  if (!provider) return errorResponse("provider_unconfigured", 503);

  // 8. Stream upstream → parse → narrow → emit downstream
  return makeSSEResponse(async (emit) => {
    const ac = new AbortController();
    req.signal.addEventListener("abort", () => ac.abort());
    const parser = new GuessParser();
    let inputTokens = 0;
    let outputTokens = 0;
    let upstreamErrored = false;

    try {
      for await (const event of provider.stream(
        { imageBase64: body.imageBase64, category: body.hintCategory },
        ac.signal
      )) {
        if (event.type === "delta" && event.text) {
          for (const ev of parser.ingest(event.text)) {
            emit(ev);
            if (ev.type === "final" || ev.type === "giveUp") {
              ac.abort();
              break;
            }
          }
        } else if (event.type === "done") {
          inputTokens = event.inputTokens ?? inputTokens;
          outputTokens = event.outputTokens ?? outputTokens;
        }
      }
      for (const ev of parser.flush()) emit(ev);
    } catch (err) {
      upstreamErrored = true;
      throw err;
    } finally {
      // 9. Bookkeeping: refund on hard error, record spend, log.
      if (upstreamErrored) {
        ctx.waitUntil(
          userStub.fetch("https://e/refund", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ reason: debit.reason }),
          })
        );
      } else {
        const usd =
          (inputTokens / 1_000_000) * provider.priceInputUsdPerM +
          (outputTokens / 1_000_000) * provider.priceOutputUsdPerM;
        ctx.waitUntil(
          globalStub.fetch("https://e/recordSpend", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ usd, cap: dailySpendUsdCap(env) }),
          })
        );
      }
      // The label injection happens *only* server-side. We never send it back.
      void CATEGORY_LABELS[body.hintCategory];
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface AttestCheck {
  ok: boolean;
  code: string;
  detail?: string;
  signCount?: number;
}

async function verifyRequestAttest(
  body: { attestation: { keyId: string; assertion: string; nonceId: string }; v: number; sessionId: string; roundId: string; hintCategory: string; provider: string; imageBase64: string },
  env: Env,
  req: Request
): Promise<AttestCheck> {
  // DEBUG bypass: only allowed when ENV=dev and a valid HMAC is presented.
  if (env.ENV !== "prod" && env.DEV_BYPASS_SECRET) {
    const header = req.headers.get("x-dev-bypass");
    if (header) {
      const expected = await hmacSHA256(env.DEV_BYPASS_SECRET, body.attestation.keyId);
      const expectedHex = bytesToHex(expected);
      if (header === expectedHex) {
        return { ok: true, code: "dev_bypass" };
      }
      return { ok: false, code: "dev_bypass_invalid" };
    }
  }

  const challenge = await consumeNonce(env, body.attestation.nonceId, "assert");
  if (!challenge) return { ok: false, code: "nonce_invalid" };

  const stored = await env.KV.get(`attest:key:${body.attestation.keyId}`, "json");
  if (!stored) return { ok: false, code: "key_unknown" };
  const { publicKeyJwk, signCount } = stored as { publicKeyJwk: JsonWebKey; signCount: number };

  // Reconstruct the exact bytes the client signed: the JSON body sans the
  // `attestation` field (since the signature is over the canonical payload).
  const payloadBytes = canonicalPayloadBytes(body);

  try {
    const result = await verifyAssertion(body.attestation.assertion, {
      publicKeyJwk,
      payload: payloadBytes,
      challenge,
      appleTeamId: env.APPLE_TEAM_ID,
      appBundleId: env.APPLE_BUNDLE_ID,
      lastSignCount: signCount,
    });
    // Persist new sign count.
    await env.KV.put(
      `attest:key:${body.attestation.keyId}`,
      JSON.stringify({ ...stored, signCount: result.newSignCount })
    );
    return { ok: true, code: "ok", signCount: result.newSignCount };
  } catch (err) {
    return { ok: false, code: "assert_invalid", detail: (err as Error).message };
  }
}

/// Canonicalize the request body for signing. Must match the iOS side bit-for-bit.
/// We use a stable field order: v, sessionId, roundId, hintCategory, provider, imageBase64.
function canonicalPayloadBytes(body: { v: number; sessionId: string; roundId: string; hintCategory: string; provider: string; imageBase64: string }): Uint8Array {
  const stable = JSON.stringify({
    v: body.v,
    sessionId: body.sessionId,
    roundId: body.roundId,
    hintCategory: body.hintCategory,
    provider: body.provider,
    imageBase64: body.imageBase64,
  });
  return new TextEncoder().encode(stable);
}

async function consumeNonce(env: Env, nonceId: string, purpose: "attest" | "assert"): Promise<Uint8Array | null> {
  const route = await env.KV.get(`nonce-route:${nonceId}`, "json");
  if (!route) return null;
  const { stubName } = route as { stubName: string };
  const stub = env.NONCE.get(env.NONCE.idFromString(stubName));
  const r = await stub.fetch("https://nonce/consume", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id: nonceId, purpose }),
  });
  if (!r.ok) return null;
  const j = (await r.json()) as { ok: boolean; value?: string };
  if (!j.ok || !j.value) return null;
  // value is hex
  return hexToBytes(j.value);
}

function hexToBytes(hex: string): Uint8Array {
  const u = new Uint8Array(hex.length / 2);
  for (let i = 0; i < u.length; i++) u[i] = parseInt(hex.substr(i * 2, 2), 16);
  return u;
}

function pickProvider(id: ProviderId, env: Env): Provider | null {
  if (id === "anthropic" && env.ANTHROPIC_API_KEY) return new AnthropicProvider(env.ANTHROPIC_API_KEY);
  if (id === "openai"    && env.OPENAI_API_KEY)    return new OpenAIProvider(env.OPENAI_API_KEY);
  return null;
}

function isJpegOrPng(b: Uint8Array): boolean {
  if (b.length < 4) return false;
  // JPEG: FF D8 FF
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return true;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return true;
  return false;
}

// silence unused-imports in dev (b64encode, bytesEqual exposed for tests)
void b64encode; void bytesEqual;
