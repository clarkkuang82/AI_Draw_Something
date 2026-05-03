import { describe, it, expect } from "vitest";
import { referralCodeFor } from "../src/referral.js";

const fakeEnv = (secret: string) => ({ REFERRAL_HMAC_SECRET: secret } as any);

describe("referralCodeFor", () => {
  it("is deterministic for the same secret + keyId", async () => {
    const a = await referralCodeFor("keyA", fakeEnv("seed"));
    const b = await referralCodeFor("keyA", fakeEnv("seed"));
    expect(a).toBe(b);
  });

  it("differs across keyIds", async () => {
    const a = await referralCodeFor("keyA", fakeEnv("seed"));
    const b = await referralCodeFor("keyB", fakeEnv("seed"));
    expect(a).not.toBe(b);
  });

  it("differs across secrets", async () => {
    const a = await referralCodeFor("keyA", fakeEnv("seed1"));
    const b = await referralCodeFor("keyA", fakeEnv("seed2"));
    expect(a).not.toBe(b);
  });

  it("uses the safe alphabet only", async () => {
    const code = await referralCodeFor("keyA", fakeEnv("seed"));
    expect(code).toMatch(/^[A-Z2-9]{6}$/);
    // No lookalikes
    expect(code).not.toMatch(/[01OI]/);
  });

  it("throws if secret is missing", async () => {
    await expect(referralCodeFor("k", {} as any)).rejects.toThrow();
  });
});
