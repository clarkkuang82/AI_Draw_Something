import { describe, it, expect } from "vitest";
import { GuessParser } from "../src/parser.js";

describe("GuessParser", () => {
  it("emits a guess event when a complete '是不是 X？' line arrives", () => {
    const p = new GuessParser();
    const events = p.ingest("是不是 飞机？\n");
    expect(events).toEqual([{ type: "guess", text: "飞机" }]);
  });

  it("accepts ASCII '?' as well as full-width '？'", () => {
    const p = new GuessParser();
    expect(p.ingest("是不是 房子?\n")).toEqual([{ type: "guess", text: "房子" }]);
  });

  it("dedupes consecutive identical guesses", () => {
    const p = new GuessParser();
    p.ingest("是不是 猫?\n");
    expect(p.ingest("是不是 猫?\n")).toEqual([]);
  });

  it("emits final on '我猜到了：X！'", () => {
    const p = new GuessParser();
    expect(p.ingest("我猜到了：吉他！\n")).toEqual([{ type: "final", guess: "吉他" }]);
  });

  it("handles partial buffer that ends with '？' but no newline", () => {
    const p = new GuessParser();
    expect(p.ingest("是不是 鱼？")).toEqual([{ type: "guess", text: "鱼" }]);
  });

  it("emits giveUp on '我猜不出来'", () => {
    const p = new GuessParser();
    expect(p.ingest("我猜不出来\n")).toEqual([{ type: "giveUp" }]);
  });

  it("ignores stray text", () => {
    const p = new GuessParser();
    expect(p.ingest("hello world\n")).toEqual([]);
  });

  it("flush emits trailing partial line when it matches", () => {
    const p = new GuessParser();
    p.ingest("是不是");
    p.ingest(" 雨伞？");
    // partial parse already fired
    const tail = p.flush();
    expect(tail).toEqual([]);
  });

  it("emits multiple guesses across deltas split mid-word", () => {
    const p = new GuessParser();
    const a = p.ingest("是不是");
    expect(a).toEqual([]);
    const b = p.ingest(" 飞机？\n是不是");
    expect(b).toEqual([{ type: "guess", text: "飞机" }]);
    const c = p.ingest(" 鱼？\n");
    expect(c).toEqual([{ type: "guess", text: "鱼" }]);
  });
});
