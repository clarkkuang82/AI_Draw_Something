/// Mirrors `Networking/GuessParser.swift`. Converts free-form text deltas
/// from the model into the narrow {guess, final, giveUp} stream we send
/// downstream. Anything that doesn't match the locked format is dropped.

import type { DownstreamEvent } from "./sse.js";

export class GuessParser {
  private buffer = "";
  private lastEmittedGuess = "";

  ingest(delta: string): DownstreamEvent[] {
    this.buffer += delta;
    const out: DownstreamEvent[] = [];
    // Split on \n or \r
    while (true) {
      const idx = firstLineBreak(this.buffer);
      if (idx < 0) break;
      const line = this.buffer.slice(0, idx);
      this.buffer = this.buffer.slice(idx + 1);
      out.push(...this.parseLine(line));
    }
    out.push(...this.parsePartial());
    return out;
  }

  flush(): DownstreamEvent[] {
    const tail = this.buffer.trim();
    this.buffer = "";
    if (!tail) return [];
    return this.parseLine(tail);
  }

  private parseLine(raw: string): DownstreamEvent[] {
    const line = raw.trim();
    if (!line) return [];
    if (line.includes("我猜到了")) {
      const g = extractAfter(["我猜到了：", "我猜到了:"], line, ["！", "!"]);
      return [{ type: "final", guess: g }];
    }
    if (line.includes("我猜不出来")) return [{ type: "giveUp" }];
    if (line.includes("是不是")) {
      const g = extractAfter(["是不是 ", "是不是"], line, ["？", "?"]);
      if (g && g !== this.lastEmittedGuess) {
        this.lastEmittedGuess = g;
        return [{ type: "guess", text: g }];
      }
    }
    return [];
  }

  private parsePartial(): DownstreamEvent[] {
    for (const marker of ["？", "?", "！", "!"]) {
      const idx = this.buffer.lastIndexOf(marker);
      if (idx < 0) continue;
      const chunk = this.buffer.slice(0, idx + 1).trim();
      if (chunk.includes("我猜到了") || chunk.includes("是不是") || chunk.includes("我猜不出来")) {
        this.buffer = this.buffer.slice(idx + 1);
        return this.parseLine(chunk);
      }
    }
    return [];
  }
}

function firstLineBreak(s: string): number {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 10 || c === 13) return i;
  }
  return -1;
}

function extractAfter(prefixes: string[], line: string, stripTail: string[]): string {
  let s = line;
  for (const p of prefixes) {
    const idx = s.indexOf(p);
    if (idx >= 0) {
      s = s.slice(idx + p.length);
      break;
    }
  }
  for (const t of stripTail) {
    if (s.endsWith(t)) s = s.slice(0, -t.length);
  }
  return s.trim();
}
