import { describe, it, expect } from "vitest";
import { b64decode, b64encode, bytesEqual, bytesToHex, concat, hmacSHA256, sha256, utcDayKey } from "../src/util.js";

describe("util", () => {
  it("hex round-trips", () => {
    const u = new Uint8Array([0, 1, 0xff, 0xab]);
    expect(bytesToHex(u)).toBe("0001ffab");
  });

  it("base64 round-trips", () => {
    const u = new Uint8Array([1, 2, 3, 250, 251]);
    expect(b64decode(b64encode(u))).toEqual(u);
  });

  it("bytesEqual is constant-time-ish", () => {
    const a = new Uint8Array([1, 2, 3]);
    const b = new Uint8Array([1, 2, 3]);
    const c = new Uint8Array([1, 2, 4]);
    expect(bytesEqual(a, b)).toBe(true);
    expect(bytesEqual(a, c)).toBe(false);
    expect(bytesEqual(a, new Uint8Array([1, 2]))).toBe(false);
  });

  it("concat preserves bytes", () => {
    const out = concat(new Uint8Array([1, 2]), new Uint8Array([3]));
    expect(Array.from(out)).toEqual([1, 2, 3]);
  });

  it("sha256 of 'abc' is the known digest", async () => {
    const h = await sha256(new TextEncoder().encode("abc"));
    expect(bytesToHex(h)).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
  });

  it("hmacSHA256 is deterministic", async () => {
    const a = await hmacSHA256("secret", "msg");
    const b = await hmacSHA256("secret", "msg");
    expect(bytesEqual(a, b)).toBe(true);
  });

  it("utcDayKey returns a YYYY-MM-DD string", () => {
    const k = utcDayKey(Date.UTC(2026, 4, 3, 12, 0, 0));
    expect(k).toBe("2026-05-03");
  });
});
