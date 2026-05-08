import Foundation

public enum TurnKind: String, Sendable, Codable {
    case aiDraws
    case playerDraws
}

public enum Difficulty: String, Sendable, Codable, CaseIterable {
    case easy, medium, hard
}

/// Coarse buckets for browsing / filtering / icon picking.
public enum WordCategory: String, Sendable, Codable, CaseIterable {
    case animal     // 动物
    case object     // 物品
    case nature     // 自然
    case food       // 食物
    case vehicle    // 交通
    case other      // 其他

    public var label: String {
        switch self {
        case .animal: return "动物"
        case .object: return "物品"
        case .nature: return "自然"
        case .food:   return "食物"
        case .vehicle: return "交通"
        case .other:  return "其他"
        }
    }

    public var emoji: String {
        switch self {
        case .animal: return "🐾"
        case .object: return "🧰"
        case .nature: return "🌿"
        case .food:   return "🍎"
        case .vehicle: return "🚗"
        case .other:  return "✦"
        }
    }
}

public struct Word: Sendable, Hashable, Codable {
    public let id: String
    public let text: String
    public let difficulty: Difficulty
    /// Extra accepted answers (English keyword, traditional Chinese, common
    /// synonyms). `id` and `text` are always considered matches; aliases let
    /// the player win with "cat" when the answer is "猫".
    public let aliases: [String]
    /// Browsable category, defaults to `.other` for back-compat.
    public let category: WordCategory

    public init(id: String,
                text: String,
                difficulty: Difficulty,
                aliases: [String] = [],
                category: WordCategory = .other) {
        self.id = id
        self.text = text
        self.difficulty = difficulty
        self.aliases = aliases
        self.category = category
    }

    /// Case-insensitive, whitespace-trimmed match against the answer, the
    /// English id, and any aliases.
    public func matches(_ guess: String) -> Bool {
        let normalized = Self.normalize(guess)
        guard !normalized.isEmpty else { return false }
        for candidate in [text, id] + aliases {
            if Self.normalize(candidate) == normalized { return true }
        }
        return false
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct Round: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let index: Int
    public let kind: TurnKind
    public let word: Word

    public init(id: UUID = UUID(), index: Int, kind: TurnKind, word: Word) {
        self.id = id
        self.index = index
        self.kind = kind
        self.word = word
    }
}

public enum Outcome: Sendable, Hashable {
    case correct(elapsed: TimeInterval)
    case timedOut
    case skipped
}

/// Game-level difficulty mode chosen at start. Controls the difficulty
/// curve `advanceToNextRound` walks.
public enum DifficultyMode: String, Sendable, Codable, CaseIterable {
    case casual    // mostly easy, one medium near the end
    case standard  // 1-2 easy, 3-4 medium, 5-6 hard (legacy default)
    case hard      // mostly hard, one medium up front
}

/// Per-round entry kept in `GameStore.roundHistory` so the GameOver screen
/// can render a per-round breakdown.
public struct RoundResult: Sendable, Hashable {
    public let round: Round
    public let outcome: Outcome
    /// Points awarded for this round (post-streak multiplier).
    public let points: Int
    /// Streak multiplier applied (1.0, 1.25, 1.5, 1.75).
    public let multiplier: Double

    public init(round: Round, outcome: Outcome, points: Int, multiplier: Double) {
        self.round = round
        self.outcome = outcome
        self.points = points
        self.multiplier = multiplier
    }

    public var didWin: Bool {
        if case .correct = outcome { return true }
        return false
    }
}
