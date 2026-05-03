import Foundation
import GameCore

/// Stateful parser that takes raw text deltas from a model and emits
/// `GuessEvent`s. Matches the locked prompt formats:
///   - 是不是 X？  (interim guess)
///   - 我猜到了：X！ (final claim — correctness decided by GameStore)
///   - 我猜不出来    (give up)
public struct GuessParser {
    private var buffer: String = ""
    private var lastEmittedGuess: String = ""

    public init() {}

    public mutating func ingest(_ delta: String) -> [GuessEvent] {
        buffer += delta
        var events: [GuessEvent] = []
        while let lineEnd = firstLineBreak(in: buffer) {
            let line = String(buffer[..<lineEnd])
            buffer.removeSubrange(...lineEnd)
            events.append(contentsOf: parseLine(line))
        }
        events.append(contentsOf: parsePartial())
        return events
    }

    public mutating func flush() -> [GuessEvent] {
        let line = buffer; buffer = ""
        return parseLine(line)
    }

    private func firstLineBreak(in s: String) -> String.Index? {
        s.firstIndex(where: { $0 == "\n" || $0 == "\r" })
    }

    private mutating func parseLine(_ raw: String) -> [GuessEvent] {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }

        if line.contains("我猜到了") {
            let g = extractAfter(["我猜到了：", "我猜到了:"], in: line, stripTail: ["！", "!"])
            return [.final(guess: g)]
        }
        if line.contains("我猜不出来") {
            return [.giveUp]
        }
        if line.contains("是不是") {
            let g = extractAfter(["是不是 ", "是不是"], in: line, stripTail: ["？", "?"])
            if g != lastEmittedGuess {
                lastEmittedGuess = g
                return [.guess(g)]
            }
        }
        return []
    }

    /// Detect a complete "是不是X?" inside the live buffer (without waiting
    /// for newline). Handles the common case where the model doesn't terminate
    /// the line.
    private mutating func parsePartial() -> [GuessEvent] {
        for marker in ["？", "?", "！", "!"] {
            if let endIdx = buffer.lastIndex(of: Character(marker)) {
                let chunk = String(buffer[...endIdx])
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("我猜到了") || trimmed.contains("是不是") {
                    buffer.removeSubrange(...endIdx)
                    return parseLine(trimmed)
                }
            }
        }
        return []
    }

    private func extractAfter(_ prefixes: [String], in line: String, stripTail: [String]) -> String {
        var s = line
        for p in prefixes {
            if let r = s.range(of: p) {
                s = String(s[r.upperBound...])
                break
            }
        }
        for t in stripTail {
            if s.hasSuffix(t) { s.removeLast(t.count) }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
