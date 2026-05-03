/// App Attest verification. References:
///   - https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server
///   - https://developer.apple.com/news/?id=1cw0z9my (App Attest WWDC21 sample)
///
/// This is the only thing standing between an extracted IPA and free Claude
/// access — it deserves careful review. Notable invariants enforced:
///   1. Leaf cert chains to Apple App Attest Root CA.
///   2. The nonce extension in the leaf cert equals SHA256(authData || clientDataHash).
///   3. authData[0..32] equals SHA256(teamId.bundleId).
///   4. AAGUID is "appattest" (prod) or "appattestdevelop" (dev).
///   5. credentialId matches keyId, which matches SHA256(public key).
///   6. Per request: signCount strictly increases.
///
/// What's NOT done:
///   - Receipt verification (separate Apple service, not required for the gate).
///   - Cert revocation check (Apple guidance is "unnecessary in normal use").

import { decode as cborDecode } from "cbor-x";
import { X509Certificate, X509ChainBuilder } from "@peculiar/x509";
import { APPLE_APP_ATTEST_ROOT_PEM } from "./cert.js";
import { bytesEqual, concat, sha256, b64decode } from "../util.js";

export interface VerifiedAttestation {
  publicKeyJwk: JsonWebKey;
  /// initial counter from authData (always 0 per Apple)
  signCount: number;
  /// 16-byte AAGUID
  aaguid: Uint8Array;
}

export interface AttestationContext {
  expectedKeyId: Uint8Array;             // base64-decoded keyId from client
  challenge: Uint8Array;                  // server-issued nonce (raw bytes)
  appleTeamId: string;
  appBundleId: string;
  /// "prod" → require "appattest" AAGUID; "dev" → also accept "appattestdevelop"
  envMode: "prod" | "dev";
}

const AAGUID_PROD = new TextEncoder().encode("appattest");          // 9 bytes
const AAGUID_DEV  = new TextEncoder().encode("appattestdevelop");  // 16 bytes
const NONCE_OID = "1.2.840.113635.100.8.2";

export async function verifyAttestation(
  attestationBase64: string,
  ctx: AttestationContext
): Promise<VerifiedAttestation> {
  const cborBytes = b64decode(attestationBase64);
  const attestation = cborDecode(cborBytes) as {
    fmt: string;
    attStmt: { x5c: Uint8Array[]; receipt: Uint8Array };
    authData: Uint8Array;
  };

  if (attestation.fmt !== "apple-appattest") {
    throw new Error(`unexpected fmt: ${attestation.fmt}`);
  }
  const x5c = attestation.attStmt?.x5c;
  if (!Array.isArray(x5c) || x5c.length < 1) {
    throw new Error("missing x5c");
  }
  const authData = attestation.authData;
  if (!(authData instanceof Uint8Array) || authData.length < 37) {
    throw new Error("malformed authData");
  }

  // 1. Cert chain to Apple root
  const leaf = new X509Certificate(x5c[0]!);
  const intermediates = x5c.slice(1).map((d) => new X509Certificate(d));
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);

  const chainBuilder = new X509ChainBuilder({ certificates: [...intermediates, root] });
  const chain = await chainBuilder.build(leaf);
  if (chain.length < 2) throw new Error("incomplete chain");
  const top = chain[chain.length - 1]!;
  if (top.serialNumber !== root.serialNumber) {
    throw new Error("chain does not anchor to Apple root");
  }

  // 2. Nonce match: SHA256(authData || clientDataHash) where
  //    clientDataHash = SHA256(challenge)
  const clientDataHash = await sha256(ctx.challenge);
  const expectedNonce = await sha256(concat(authData, clientDataHash));
  const certNonce = extractNonceFromCert(leaf);
  if (!bytesEqual(certNonce, expectedNonce)) {
    throw new Error("nonce mismatch");
  }

  // 3. rpIdHash check
  const rpIdHash = authData.slice(0, 32);
  const expectedRpIdHash = await sha256(
    new TextEncoder().encode(`${ctx.appleTeamId}.${ctx.appBundleId}`)
  );
  if (!bytesEqual(rpIdHash, expectedRpIdHash)) {
    throw new Error("rpId mismatch");
  }

  // 4. AAGUID check (bytes 37..52, 16 bytes)
  const aaguid = authData.slice(37, 53);
  if (!isAcceptableAaguid(aaguid, ctx.envMode)) {
    throw new Error(`unexpected aaguid: ${Array.from(aaguid)}`);
  }

  // 5. credentialId == keyId == SHA256(publicKey)
  if (authData.length < 55) throw new Error("authData too short for credentialId");
  const credIdLen = (authData[53]! << 8) | authData[54]!;
  if (credIdLen !== 32) throw new Error(`unexpected credIdLen ${credIdLen}`);
  const credentialId = authData.slice(55, 55 + 32);
  if (!bytesEqual(credentialId, ctx.expectedKeyId)) {
    throw new Error("credentialId != keyId");
  }

  // 6. Parse the COSE EC2 public key (after credentialId)
  const coseKeyBytes = authData.slice(55 + 32);
  const cose = cborDecode(coseKeyBytes) as Map<number, unknown> | Record<number, unknown>;
  const x = coseGet(cose, -2);
  const y = coseGet(cose, -3);
  if (!(x instanceof Uint8Array) || !(y instanceof Uint8Array) || x.length !== 32 || y.length !== 32) {
    throw new Error("malformed COSE key");
  }
  const publicKeyJwk: JsonWebKey = {
    kty: "EC",
    crv: "P-256",
    x: bytesToB64Url(x),
    y: bytesToB64Url(y),
  };

  // 7. keyId must equal SHA256(uncompressed public key (0x04 || x || y))
  const ecPoint = concat(new Uint8Array([0x04]), x, y);
  const ecHash = await sha256(ecPoint);
  if (!bytesEqual(ecHash, ctx.expectedKeyId)) {
    throw new Error("keyId != SHA256(publicKey)");
  }

  // 8. Counter is bytes 33..37 (BE u32). Apple says always 0 on attest.
  const signCount = (authData[33]! << 24) | (authData[34]! << 16) | (authData[35]! << 8) | authData[36]!;
  if (signCount !== 0) {
    // Not a fatal error per spec, but unexpected.
  }

  return { publicKeyJwk, signCount, aaguid };
}

// ---------------- Assertion verification ----------------

export interface AssertionContext {
  publicKeyJwk: JsonWebKey;
  /// the body bytes the client signed
  payload: Uint8Array;
  /// server-issued nonce (raw bytes)
  challenge: Uint8Array;
  appleTeamId: string;
  appBundleId: string;
  /// monotonically increasing counter; verification requires the new value
  /// strictly exceeds this.
  lastSignCount: number;
}

export interface VerifiedAssertion {
  newSignCount: number;
}

export async function verifyAssertion(
  assertionBase64: string,
  ctx: AssertionContext
): Promise<VerifiedAssertion> {
  const decoded = cborDecode(b64decode(assertionBase64)) as {
    signature: Uint8Array;
    authenticatorData: Uint8Array;
  };
  const sigDer = decoded.signature;
  const authData = decoded.authenticatorData;

  // rpIdHash check
  const rpIdHash = authData.slice(0, 32);
  const expectedRpIdHash = await sha256(
    new TextEncoder().encode(`${ctx.appleTeamId}.${ctx.appBundleId}`)
  );
  if (!bytesEqual(rpIdHash, expectedRpIdHash)) {
    throw new Error("rpId mismatch");
  }

  // counter
  const newSignCount =
    (authData[33]! << 24) | (authData[34]! << 16) | (authData[35]! << 8) | authData[36]!;
  if (newSignCount <= ctx.lastSignCount) {
    throw new Error(`replay: counter ${newSignCount} <= ${ctx.lastSignCount}`);
  }

  // nonce/signature
  const clientDataHash = await sha256(concat(ctx.payload, ctx.challenge));
  const nonce = await sha256(concat(authData, clientDataHash));

  const sigRaw = derEcdsaToRaw(sigDer);
  const key = await crypto.subtle.importKey(
    "jwk",
    ctx.publicKeyJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    sigRaw,
    nonce
  );
  if (!ok) throw new Error("signature invalid");

  return { newSignCount };
}

// ---------------- helpers ----------------

function isAcceptableAaguid(aaguid: Uint8Array, envMode: "prod" | "dev"): boolean {
  // AAGUID is 16 bytes, right-padded with zeros if shorter.
  const matchPadded = (probe: Uint8Array): boolean => {
    if (aaguid.length !== 16) return false;
    if (probe.length > 16) return false;
    for (let i = 0; i < probe.length; i++) if (aaguid[i] !== probe[i]) return false;
    for (let i = probe.length; i < 16; i++) if (aaguid[i] !== 0) return false;
    return true;
  };
  if (matchPadded(AAGUID_PROD)) return true;
  if (envMode === "dev" && matchPadded(AAGUID_DEV)) return true;
  return false;
}

function extractNonceFromCert(cert: X509Certificate): Uint8Array {
  const ext = cert.extensions.find((e) => e.type === NONCE_OID);
  if (!ext) throw new Error(`no ${NONCE_OID} extension`);
  // The extension value is an OCTET STRING wrapping a SEQUENCE { [1] OCTET STRING nonce }.
  // ext.value gives us the OCTET STRING contents (i.e. the SEQUENCE bytes).
  const seqBytes = new Uint8Array(ext.value);
  // Lightweight DER parse: SEQUENCE (30 LL) -> [1] (a1 LL) -> OCTET STRING (04 LL)
  let p = 0;
  if (seqBytes[p++] !== 0x30) throw new Error("nonce ext: expect SEQUENCE");
  const seqLen = readDerLen(seqBytes, p);
  p = seqLen.next;
  // Inner: context-specific [1]
  if (seqBytes[p++] !== 0xa1) throw new Error("nonce ext: expect [1]");
  const ctxLen = readDerLen(seqBytes, p);
  p = ctxLen.next;
  // OCTET STRING
  if (seqBytes[p++] !== 0x04) throw new Error("nonce ext: expect OCTET STRING");
  const octLen = readDerLen(seqBytes, p);
  p = octLen.next;
  return seqBytes.slice(p, p + octLen.length);
}

function readDerLen(buf: Uint8Array, p: number): { length: number; next: number } {
  const first = buf[p]!;
  if (first < 0x80) return { length: first, next: p + 1 };
  const n = first & 0x7f;
  let len = 0;
  for (let i = 1; i <= n; i++) len = (len << 8) | buf[p + i]!;
  return { length: len, next: p + 1 + n };
}

function coseGet(m: Map<number, unknown> | Record<number, unknown>, key: number): unknown {
  if (m instanceof Map) return m.get(key);
  return (m as Record<number, unknown>)[key];
}

function bytesToB64Url(u: Uint8Array): string {
  let s = "";
  for (let i = 0; i < u.length; i++) s += String.fromCharCode(u[i]!);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Convert an ECDSA SEQUENCE { r INTEGER, s INTEGER } DER signature into the
/// raw IEEE-P1363 form (r || s, 32 bytes each) that WebCrypto expects.
function derEcdsaToRaw(der: Uint8Array): Uint8Array {
  let p = 0;
  if (der[p++] !== 0x30) throw new Error("ecdsa DER: expect SEQUENCE");
  const seq = readDerLen(der, p);
  p = seq.next;
  const readInt = (): Uint8Array => {
    if (der[p++] !== 0x02) throw new Error("ecdsa DER: expect INTEGER");
    const len = readDerLen(der, p);
    p = len.next;
    let v = der.slice(p, p + len.length);
    p += len.length;
    // strip leading zero
    while (v.length > 32 && v[0] === 0x00) v = v.slice(1);
    if (v.length > 32) throw new Error("ecdsa DER: integer too long");
    if (v.length < 32) {
      const padded = new Uint8Array(32);
      padded.set(v, 32 - v.length);
      v = padded;
    }
    return v;
  };
  const r = readInt();
  const s = readInt();
  return concat(r, s);
}
