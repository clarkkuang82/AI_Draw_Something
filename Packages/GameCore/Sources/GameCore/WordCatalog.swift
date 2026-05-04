import Foundation

public protocol WordCatalog: Sendable {
    func pick(difficulty: Difficulty, excluding: Set<String>) -> Word?
    var allCategoryIds: [String] { get }
}

/// In-memory catalog backed by a small static list. The full QuickDraw
/// curation (~100 categories × 30 sketches) replaces this in v2.
public struct StaticWordCatalog: WordCatalog, Sendable {
    public let words: [Word]

    public init(words: [Word]) { self.words = words }

    public var allCategoryIds: [String] { words.map(\.id) }

    public func pick(difficulty: Difficulty, excluding: Set<String>) -> Word? {
        let pool = words.filter { $0.difficulty == difficulty && !excluding.contains($0.id) }
        return pool.randomElement() ?? words.filter { !excluding.contains($0.id) }.randomElement()
    }

    /// Hand-curated MVP seed list. Mirrors the categories in the bundled
    /// `quickdraw.bundle/sketches.json`.
    public static let mvpSeed: StaticWordCatalog = .init(words: [
        Word(id: "cat",      text: "猫",   difficulty: .easy),
        Word(id: "fish",     text: "鱼",   difficulty: .easy),
        Word(id: "house",    text: "房子", difficulty: .easy),
        Word(id: "airplane", text: "飞机", difficulty: .medium),
        Word(id: "umbrella", text: "雨伞", difficulty: .medium),
        Word(id: "guitar",   text: "吉他", difficulty: .hard),
    ])
}
