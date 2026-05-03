import { DurableObject } from "cloudflare:workers";
import { bytesToHex } from "../util.js";

interface NonceRecord {
  value: string;        // hex of 32 random bytes
  purpose: "attest" | "assert";
  expiresAt: number;    // unix ms
  consumed: boolean;
}

const TTL_MS = 60_000;

/// One nonce per id, single-use, 60s TTL. The Worker calls `issue()` to
/// hand out a nonce and `consume()` to atomically validate-and-burn it.
export class NonceDO extends DurableObject {
  override async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    if (req.method === "POST" && url.pathname === "/issue") {
      const { purpose } = (await req.json()) as { purpose: "attest" | "assert" };
      const id = crypto.randomUUID();
      const buf = new Uint8Array(32);
      crypto.getRandomValues(buf);
      const value = bytesToHex(buf);
      const rec: NonceRecord = {
        value,
        purpose,
        expiresAt: Date.now() + TTL_MS,
        consumed: false,
      };
      await this.ctx.storage.put(`n:${id}`, rec);
      // Set alarm to GC the row.
      await this.ctx.storage.setAlarm(rec.expiresAt + 1_000);
      return Response.json({ id, value, expiresAt: rec.expiresAt });
    }

    if (req.method === "POST" && url.pathname === "/consume") {
      const { id, purpose } = (await req.json()) as { id: string; purpose: "attest" | "assert" };
      const rec = await this.ctx.storage.get<NonceRecord>(`n:${id}`);
      if (!rec) return Response.json({ ok: false, reason: "missing" }, { status: 404 });
      if (rec.consumed) return Response.json({ ok: false, reason: "consumed" }, { status: 409 });
      if (rec.expiresAt < Date.now()) return Response.json({ ok: false, reason: "expired" }, { status: 410 });
      if (rec.purpose !== purpose) return Response.json({ ok: false, reason: "purpose" }, { status: 400 });
      rec.consumed = true;
      await this.ctx.storage.put(`n:${id}`, rec);
      return Response.json({ ok: true, value: rec.value });
    }

    return new Response("not found", { status: 404 });
  }

  override async alarm(): Promise<void> {
    const now = Date.now();
    const all = await this.ctx.storage.list<NonceRecord>({ prefix: "n:" });
    const expired: string[] = [];
    for (const [k, v] of all) if (v.expiresAt < now) expired.push(k);
    if (expired.length) await this.ctx.storage.delete(expired);
  }
}
