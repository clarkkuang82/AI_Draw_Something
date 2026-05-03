/// Verify Apple StoreKit 2 / App Store Server JWS payloads.
///
/// Apple signs each transaction (and each server-to-server notification)
/// as a JWS with an x5c header. The leaf cert's public key signs the JWS;
/// the chain anchors to Apple Root CA G3. We do everything locally — no
/// network call to verify a transaction.

import { X509Certificate, X509ChainBuilder } from "@peculiar/x509";
import { importX509, jwtVerify, decodeProtectedHeader, type JWTPayload } from "jose";
import { APPLE_ROOT_CA_G3_PEM } from "../attest/cert.js";

export interface VerifiedJWS<T extends JWTPayload = JWTPayload> {
  payload: T;
  /// SHA-256 hex of the leaf cert (for audit).
  leafFingerprint: string;
  /// Environment hint from the payload (Sandbox vs Production).
  environment: string | undefined;
}

/// Verify a JWS string. Throws on any chain / signature failure.
export async function verifyAppleJWS<T extends JWTPayload = JWTPayload>(jws: string): Promise<VerifiedJWS<T>> {
  const header = decodeProtectedHeader(jws);
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length === 0) throw new Error("jws: missing x5c");

  const certs = x5c.map((b64) => new X509Certificate(b64));
  const leaf = certs[0]!;
  const intermediates = certs.slice(1);
  const root = new X509Certificate(APPLE_ROOT_CA_G3_PEM);

  const chain = await new X509ChainBuilder({
    certificates: [...intermediates, root],
  }).build(leaf);
  if (chain.length < 2) throw new Error("jws: incomplete chain");
  const top = chain[chain.length - 1]!;
  if (top.serialNumber !== root.serialNumber) {
    throw new Error("jws: not anchored to Apple Root CA G3");
  }

  // Build a CryptoKey from the leaf cert and verify the JWS.
  const pemLeaf = certToPem(x5c[0]!);
  const alg = header.alg ?? "ES256";
  const key = await importX509(pemLeaf, alg);
  const { payload } = await jwtVerify(jws, key, { algorithms: [alg] });

  return {
    payload: payload as T,
    leafFingerprint: await sha256Hex(new Uint8Array(leaf.rawData)),
    environment: typeof (payload as Record<string, unknown>).environment === "string"
      ? (payload as Record<string, string>).environment
      : undefined,
  };
}

function certToPem(b64Der: string): string {
  // Re-wrap the cert into PEM so jose can read it.
  const lines: string[] = [];
  for (let i = 0; i < b64Der.length; i += 64) lines.push(b64Der.slice(i, i + 64));
  return `-----BEGIN CERTIFICATE-----\n${lines.join("\n")}\n-----END CERTIFICATE-----`;
}

async function sha256Hex(buf: Uint8Array): Promise<string> {
  const out = new Uint8Array(await crypto.subtle.digest("SHA-256", buf));
  let hex = "";
  for (let i = 0; i < out.length; i++) hex += out[i]!.toString(16).padStart(2, "0");
  return hex;
}

// ---------------------------------------------------------------------------
// Apple JWS payload shapes (just the fields we use)
// ---------------------------------------------------------------------------

export interface JWSTransactionPayload extends JWTPayload {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  /// "Consumable" | "Non-Consumable" | "Auto-Renewable Subscription" | ...
  type: string;
  purchaseDate: number;       // ms since epoch
  expiresDate?: number;       // ms; subscriptions only
  inAppOwnershipType?: string;
  appAccountToken?: string;   // we set this to the keyId on the iOS side (optional)
  bundleId: string;
  environment: "Sandbox" | "Production";
}

export interface JWSNotificationPayload extends JWTPayload {
  notificationType:
    | "REFUND" | "REVOKE" | "EXPIRED" | "DID_RENEW"
    | "DID_FAIL_TO_RENEW" | "GRACE_PERIOD_EXPIRED" | "PRICE_INCREASE"
    | "SUBSCRIBED" | "DID_CHANGE_RENEWAL_STATUS" | "OFFER_REDEEMED"
    | "REFUND_DECLINED" | "RENEWAL_EXTENDED" | "TEST" | string;
  subtype?: string;
  notificationUUID: string;
  data?: {
    /// signedTransactionInfo and signedRenewalInfo are themselves JWS strings
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
    bundleId?: string;
    environment?: string;
  };
}
