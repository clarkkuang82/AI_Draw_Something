import { z } from "zod";

/// The closed set of category ids supported by the game. Must mirror the
/// ids in the iOS bundle's WordCatalog. Anything outside this set is
/// rejected before reaching the model.
export const CATEGORY_IDS = [
  "cat",
  "fish",
  "house",
  "airplane",
  "umbrella",
  "guitar",
] as const;

export const CategoryEnum = z.enum(CATEGORY_IDS);
export type CategoryId = z.infer<typeof CategoryEnum>;

/// id → localized label (Chinese). Used by the Worker when constructing
/// the user message (the model never receives free-form strings from the
/// client, only an enum index).
export const CATEGORY_LABELS: Record<CategoryId, string> = {
  cat: "猫",
  fish: "鱼",
  house: "房子",
  airplane: "飞机",
  umbrella: "雨伞",
  guitar: "吉他",
};

export const ProviderEnum = z.enum(["anthropic", "openai"]);
export type ProviderId = z.infer<typeof ProviderEnum>;

export const AttestationZ = z
  .object({
    keyId: z.string().min(1).max(256),
    assertion: z.string().min(1).max(4096), // base64
    nonceId: z.string().min(1).max(128),
  })
  .strict();

export const GuessRequestZ = z
  .object({
    v: z.literal(1),
    sessionId: z.string().uuid(),
    roundId: z.string().uuid(),
    hintCategory: CategoryEnum,
    provider: ProviderEnum,
    imageBase64: z.string().max(200_000),
    attestation: AttestationZ,
  })
  .strict();

export type GuessRequest = z.infer<typeof GuessRequestZ>;

export const NonceRequestZ = z
  .object({ purpose: z.enum(["attest", "assert"]) })
  .strict();

export const AttestRegisterZ = z
  .object({
    keyId: z.string().min(1).max(256),
    attestationBase64: z.string().min(1).max(8192),
    challengeId: z.string().min(1).max(128),
  })
  .strict();
