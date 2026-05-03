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

    public init(id: String, text: String, difficulty: Difficulty) {
        self.id = id
        self.text = text
        self.difficulty = difficulty
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
