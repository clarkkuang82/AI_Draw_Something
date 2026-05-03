// Small helpers used across the Worker. Nothing here is hot-path enough to
// warrant heroic performance work — clarity wins.

const HEX = "0123456789abcdef";

export function bytesToHex(buf: ArrayBuffer | Uint8Array): string {
  const u = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let out = "";
  for (let i = 0; i < u.length; i++) {
    out += HEX[u[i]! >> 4] + HEX[u[i]! & 0xf];
  }
  return out;
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

export function b64decode(s: string): Uint8Array {
  // accepts standard or url-safe
  const std = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = std.length % 4 === 0 ? std : std + "=".repeat(4 - (std.length % 4));
  const bin = atob(pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64encode(u: Uint8Array): string {
  let s = "";
  for (let i = 0; i < u.length; i++) s += String.fromCharCode(u[i]!);
  return btoa(s);
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const buf = await crypto.subtle.digest("SHA-256", data);
  return new Uint8Array(buf);
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

export function utcDayKey(now: number = Date.now()): string {
  return new Date(now).toISOString().slice(0, 10); // "YYYY-MM-DD"
}

export function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

export function errorResponse(code: string, status: number, detail?: string): Response {
  return jsonResponse({ error: code, detail }, status);
}

export async function hmacSHA256(secret: string, msg: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg));
  return new Uint8Array(sig);
}

/** Reads at most `cap` bytes from a request body. Throws on overrun. */
export async function readJsonBody<T>(req: Request, cap = 256_000): Promise<T> {
  const text = await req.text();
  if (text.length > cap) throw new Error(`payload too large: ${text.length} > ${cap}`);
  return JSON.parse(text) as T;
}
