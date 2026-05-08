import Foundation

public enum TurnKind: String, Sendable, Codable {
    case aiDraws
    case playerDraws
}

public enum Difficulty: String, Sendable, Codable, CaseIterable {
    case easy, medium, hard
}

public struct Word: Sendable, Hashable, Codable {
    public let id: String
    public let text: String
    public let difficulty: Difficulty
    /// Extra accepted answers (English keyword, traditional Chinese, common
    /// synonyms). `id` and `text` are always considered matches; aliases let
    /// the player win with "cat" when the answer is "猫".
    public let aliases: [String]

    public init(id: String, text: String, difficulty: Difficulty, aliases: [String] = []) {
        self.id = id
        self.text = text
        self.difficulty = difficulty
        self.aliases = aliases
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
