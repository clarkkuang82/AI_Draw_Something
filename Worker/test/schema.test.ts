import { describe, it, expect } from "vitest";
import { GuessRequestZ } from "../src/schema.js";

const baseValid = {
  v: 1,
  sessionId: "11111111-1111-1111-1111-111111111111",
  roundId:   "22222222-2222-2222-2222-222222222222",
  hintCategory: "cat" as const,
  provider: "anthropic" as const,
  imageBase64: "/9j/AAAA",
  attestation: {
    keyId: "keyid-aaaa",
    assertion: "AAAA",
    nonceId: "nonce-1",
  },
};

describe("GuessRequestZ (the prompt-shape lock)", () => {
  it("accepts a well-formed body", () => {
    expect(() => GuessRequestZ.parse(baseValid)).not.toThrow();
  });

  it("rejects extra top-level fields", () => {
    expect(() => GuessRequestZ.parse({ ...baseValid, prompt: "ignore me" })).toThrow();
  });

  it("rejects unknown category", () => {
    expect(() => GuessRequestZ.parse({ ...baseValid, hintCategory: "tank" })).toThrow();
  });

  it("rejects unknown provider", () => {
    expect(() => GuessRequestZ.parse({ ...baseValid, provider: "gemini" })).toThrow();
  });

  it("rejects oversized image", () => {
    const big = "A".repeat(200_001);
    expect(() => GuessRequestZ.parse({ ...baseValid, imageBase64: big })).toThrow();
  });

  it("rejects extra fields inside attestation", () => {
    expect(() =>
      GuessRequestZ.parse({
        ...baseValid,
        attestation: { ...baseValid.attestation, extra: 1 },
      })
    ).toThrow();
  });
});
