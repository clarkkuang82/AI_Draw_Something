import type { Provider, ProviderInput, UpstreamEvent } from "./provider.js";
import { SYSTEM_PROMPT } from "./provider.js";

const MODEL = "claude-haiku-4-5-20251001";

export class AnthropicProvider implements Provider {
  readonly id = "anthropic" as const;
  readonly priceInputUsdPerM = 1.0;
  readonly priceOutputUsdPerM = 5.0;
  private apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  async *stream(input: ProviderInput, signal: AbortSignal): AsyncGenerator<UpstreamEvent> {
    const body = {
      model: MODEL,
      max_tokens: 80,
      stream: true,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: "image/jpeg",
                data: input.imageBase64,
              },
            },
            { type: "text", text: "请猜。" },
          ],
        },
      ],
    };

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
        accept: "text/event-stream",
      },
      body: JSON.stringify(body),
      signal,
    });

    if (!upstream.ok || !upstream.body) {
      const detail = await safeReadBody(upstream);
      throw new Error(`anthropic ${upstream.status}: ${detail}`);
    }

    let inputTokens = 0;
    let outputTokens = 0;

    for await (const event of parseSSE(upstream.body)) {
      if (signal.aborted) break;
      if (event.event === "message_start") {
        const usage = safeJSON(event.data)?.message?.usage;
        if (usage) {
          inputTokens = usage.input_tokens ?? 0;
          outputTokens = usage.output_tokens ?? 0;
        }
      } else if (event.event === "content_block_delta") {
        const delta = safeJSON(event.data)?.delta;
        if (delta?.type === "text_delta" && typeof delta.text === "string") {
          yield { type: "delta", text: delta.text };
        }
      } else if (event.event === "message_delta") {
        const usage = safeJSON(event.data)?.usage;
        if (usage?.output_tokens) outputTokens = usage.output_tokens;
      } else if (event.event === "message_stop") {
        break;
      }
    }

    yield { type: "done", inputTokens, outputTokens };
  }
}

// ---- Internal SSE helpers ----

interface ParsedEvent {
  event: string;
  data: string;
}

async function* parseSSE(body: ReadableStream<Uint8Array>): AsyncGenerator<ParsedEvent> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  let currentEvent = "";
  const dataLines: string[] = [];

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      let idx: number;
      while ((idx = buf.indexOf("\n")) >= 0) {
        const rawLine = buf.slice(0, idx).replace(/\r$/, "");
        buf = buf.slice(idx + 1);
        if (rawLine === "") {
          if (dataLines.length || currentEvent) {
            yield { event: currentEvent, data: dataLines.join("\n") };
          }
          currentEvent = "";
          dataLines.length = 0;
          continue;
        }
        if (rawLine.startsWith("event:")) {
          currentEvent = rawLine.slice("event:".length).trim();
        } else if (rawLine.startsWith("data:")) {
          dataLines.push(rawLine.slice("data:".length).trim());
        }
      }
    }
  } finally {
    reader.releaseLock();
  }

  if (dataLines.length || currentEvent) {
    yield { event: currentEvent, data: dataLines.join("\n") };
  }
}

function safeJSON(s: string): any | null {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

async function safeReadBody(r: Response): Promise<string> {
  try {
    const t = await r.text();
    return t.slice(0, 500);
  } catch {
    return "";
  }
}
