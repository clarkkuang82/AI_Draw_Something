import { describe, it, expect } from "vitest";

/// Mirror of `Packages/Networking/Tests/NetworkingTests/CanonicalPayloadTests.swift`.
/// If this fixture changes, update the Swift one too. Byte-for-byte match
/// with the iOS canonical encoding is what makes App Attest signatures
/// validate.

const FIXTURE_BODY = {
  hintCategory: "cat",
  imageBase64: "/9j/AAAA",
  provider: "anthropic",
  roundId: "11111111-1111-1111-1111-111111111111",
  sessionId: "22222222-2222-2222-2222-222222222222",
  v: 1,
};

const EXPECTED =
  '{"hintCategory":"cat","imageBase64":"/9j/AAAA","provider":"anthropic","roundId":"11111111-1111-1111-1111-111111111111","sessionId":"22222222-2222-2222-2222-222222222222","v":1}';

/// Re-implementation of the Worker's canonicalPayloadBytes() for testing —
/// keeping it inline so this file is self-contained. The real one in
/// `src/index.ts` MUST produce the same bytes.
function canonical(body: typeof FIXTURE_BODY): string {
  const obj: Record<string, unknown> = {
    hintCategory: body.hintCategory,
    imageBase64: body.imageBase64,
    provider: body.provider,
    roundId: body.roundId,
    sessionId: body.sessionId,
    v: body.v,
  };
  return JSON.stringify(obj);
}

describe("canonical payload (TS half of cross-platform pin)", () => {
  it("produces the pinned fixture bytes", () => {
    expect(canonical(FIXTURE_BODY)).toBe(EXPECTED);
  });

  it("does not escape forward slashes (matches Swift withoutEscapingSlashes)", () => {
    const json = canonical(FIXTURE_BODY);
    expect(json).toContain("/9j/AAAA");
    expect(json).not.toContain("\\/");
  });

  it("emits keys in alphabetical order regardless of construction order", () => {
    const reordered = {
      v: 1,
      sessionId: "22222222-2222-2222-2222-222222222222",
      roundId: "11111111-1111-1111-1111-111111111111",
      provider: "anthropic",
      imageBase64: "/9j/AAAA",
      hintCategory: "cat",
    };
    // The Worker always inserts keys alphabetically so the output is
    // deterministic. If you write `JSON.stringify(reordered)` directly,
    // you'd get a different string — that's exactly the trap.
    expect(canonical(reordered as typeof FIXTURE_BODY)).toBe(EXPECTED);
  });
});
