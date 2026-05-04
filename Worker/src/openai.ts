import type { Provider, ProviderInput, UpstreamEvent } from "./provider.js";
import { SYSTEM_PROMPT } from "./provider.js";

const MODEL = "gpt-4o-mini";

export class OpenAIProvider implements Provider {
  readonly id = "openai" as const;
  readonly priceInputUsdPerM = 0.15;
  readonly priceOutputUsdPerM = 0.60;
  private apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  async *stream(input: ProviderInput, signal: AbortSignal): AsyncGenerator<UpstreamEvent> {
    const body = {
      model: MODEL,
      max_tokens: 80,
      stream: true,
      stream_options: { include_usage: true },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            { type: "text", text: "请猜。" },
            {
              type: "image_url",
              image_url: { url: `data:image/jpeg;base64,${input.imageBase64}` },
            },
          ],
        },
      ],
    };

    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${this.apiKey}`,
        accept: "text/event-stream",
      },
      body: JSON.stringify(body),
      signal,
    });

    if (!upstream.ok || !upstream.body) {
      const detail = await safeReadBody(upstream);
      throw new Error(`openai ${upstream.status}: ${detail}`);
    }

    let inputTokens = 0;
    let outputTokens = 0;
    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";

    try {
      outer: while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (signal.aborted) break;
        buf += decoder.decode(value, { stream: true });

        let idx: number;
        while ((idx = buf.indexOf("\n")) >= 0) {
          const rawLine = buf.slice(0, idx).replace(/\r$/, "");
          buf = buf.slice(idx + 1);
          if (!rawLine.startsWith("data:")) continue;
          const payload = rawLine.slice("data:".length).trim();
          if (payload === "[DONE]") break outer;

          let obj: any;
          try { obj = JSON.parse(payload); } catch { continue; }

          const usage = obj.usage;
          if (usage) {
            inputTokens = usage.prompt_tokens ?? inputTokens;
            outputTokens = usage.completion_tokens ?? outputTokens;
          }
          const delta = obj.choices?.[0]?.delta?.content;
          if (typeof delta === "string" && delta.length > 0) {
            yield { type: "delta", text: delta };
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    yield { type: "done", inputTokens, outputTokens };
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
