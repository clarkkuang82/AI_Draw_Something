import type { CategoryId, ProviderId } from "./schema.js";

export interface UpstreamEvent {
  type: "delta" | "done";
  text?: string;
  /// Reported on `done` for the spend killswitch.
  inputTokens?: number;
  outputTokens?: number;
}

export interface ProviderInput {
  imageBase64: string;
  category: CategoryId;
}

export interface Provider {
  readonly id: ProviderId;
  /// Per-1M-token prices (input, output) in USD. Used by SpendDO.
  readonly priceInputUsdPerM: number;
  readonly priceOutputUsdPerM: number;
  stream(input: ProviderInput, signal: AbortSignal): AsyncGenerator<UpstreamEvent>;
}

/// Locked system prompt. Identical for both providers so behaviour is comparable.
/// `category` is intentionally NOT included — the model has to actually identify
/// the drawing rather than just confirm. Future v2 will swap in 4 candidate
/// distractors for a closed candidate set.
export const SYSTEM_PROMPT = `你在玩看图猜词。仅按以下两种格式之一输出，每次只回一行，不超过 8 个汉字，
不解释、不寒暄、不复述提示：
  猜测时：「是不是 X？」
  确信时：「我猜到了：X！」
最多 3 次猜测，超过即输出「我猜不出来」。
每行一个猜测，按可能性从高到低排序。`;
