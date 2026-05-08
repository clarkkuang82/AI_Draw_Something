import Foundation

public protocol WordCatalog: Sendable {
    /// Pick a word for the given difficulty, optionally restricted to a subset
    /// of category ids (used to limit AI-draws rounds to the categories that
    /// actually have sketches in the bundled dataset). When the tier+restriction
    /// produces no candidate, falls back to any non-excluded word.
    func pick(difficulty: Difficulty, restrictedTo: Set<String>?, excluding: Set<String>) -> Word?
    var allCategoryIds: [String] { get }
}

public extension WordCatalog {
    /// Backward-compatible overload. Equivalent to passing `restrictedTo: nil`.
    func pick(difficulty: Difficulty, excluding: Set<String>) -> Word? {
        pick(difficulty: difficulty, restrictedTo: nil, excluding: excluding)
    }
}

/// In-memory catalog backed by a small static list. The full QuickDraw
/// curation (~100 categories × 30 sketches) replaces this in v2.
public struct StaticWordCatalog: WordCatalog, Sendable {
    public let words: [Word]

    public init(words: [Word]) { self.words = words }

    public var allCategoryIds: [String] { words.map(\.id) }

    public func pick(difficulty: Difficulty, restrictedTo: Set<String>?, excluding: Set<String>) -> Word? {
        let baseFiltered = words.filter { word in
            !excluding.contains(word.id) &&
                (restrictedTo.map { $0.contains(word.id) } ?? true)
        }
        if let pick = baseFiltered.filter({ $0.difficulty == difficulty }).randomElement() {
            return pick
        }
        return baseFiltered.randomElement()
    }

    /// Hand-curated MVP seed list. The first six categories also have stroke
    /// data in `Drawing/Resources/sketches.json` and can show up in AI-draws
    /// rounds; the rest are player-draws-only (the player still draws them
    /// with PencilKit and the VLM guesses).
    public static let mvpSeed: StaticWordCatalog = .init(words: [
        // — easy —
        Word(id: "cat",      text: "猫",   difficulty: .easy,   aliases: ["cat", "kitty", "kitten", "猫咪"]),
        Word(id: "fish",     text: "鱼",   difficulty: .easy,   aliases: ["fish", "魚"]),
        Word(id: "house",    text: "房子", difficulty: .easy,   aliases: ["house", "home", "屋", "房屋"]),
        Word(id: "apple",    text: "苹果", difficulty: .easy,   aliases: ["apple", "蘋果"]),
        Word(id: "sun",      text: "太阳", difficulty: .easy,   aliases: ["sun", "太陽"]),
        Word(id: "moon",     text: "月亮", difficulty: .easy,   aliases: ["moon", "月"]),
        Word(id: "star",     text: "星星", difficulty: .easy,   aliases: ["star", "星"]),
        Word(id: "tree",     text: "树",   difficulty: .easy,   aliases: ["tree", "樹"]),
        Word(id: "flower",   text: "花",   difficulty: .easy,   aliases: ["flower", "blossom"]),
        Word(id: "heart",    text: "心",   difficulty: .easy,   aliases: ["heart", "love", "愛心"]),
        // — medium —
        Word(id: "airplane", text: "飞机", difficulty: .medium, aliases: ["airplane", "plane", "aircraft", "飛機"]),
        Word(id: "umbrella", text: "雨伞", difficulty: .medium, aliases: ["umbrella", "雨傘", "伞"]),
        Word(id: "bicycle",  text: "自行车", difficulty: .medium, aliases: ["bicycle", "bike", "单车", "腳踏車"]),
        Word(id: "car",      text: "汽车", difficulty: .medium, aliases: ["car", "auto", "automobile", "車"]),
        Word(id: "clock",    text: "时钟", difficulty: .medium, aliases: ["clock", "watch", "钟", "鐘"]),
        Word(id: "glasses",  text: "眼镜", difficulty: .medium, aliases: ["glasses", "spectacles", "眼鏡"]),
        Word(id: "hat",      text: "帽子", difficulty: .medium, aliases: ["hat", "cap"]),
        Word(id: "shoe",     text: "鞋",   difficulty: .medium, aliases: ["shoe", "shoes", "鞋子"]),
        Word(id: "book",     text: "书",   difficulty: .medium, aliases: ["book", "書"]),
        Word(id: "chair",    text: "椅子", difficulty: .medium, aliases: ["chair", "seat"]),
        // — hard —
        Word(id: "guitar",   text: "吉他", difficulty: .hard,   aliases: ["guitar"]),
        Word(id: "piano",    text: "钢琴", difficulty: .hard,   aliases: ["piano", "鋼琴"]),
        Word(id: "butterfly",text: "蝴蝶", difficulty: .hard,   aliases: ["butterfly", "蝶"]),
        Word(id: "giraffe",  text: "长颈鹿", difficulty: .hard, aliases: ["giraffe", "長頸鹿"]),
        Word(id: "elephant", text: "大象", difficulty: .hard,   aliases: ["elephant"]),
        Word(id: "dragon",   text: "龙",   difficulty: .hard,   aliases: ["dragon", "龍"]),
        Word(id: "train",    text: "火车", difficulty: .hard,   aliases: ["train", "火車"]),
        Word(id: "helicopter",text: "直升机", difficulty: .hard, aliases: ["helicopter", "chopper", "直升機"]),
        Word(id: "kite",     text: "风筝", difficulty: .hard,   aliases: ["kite", "風箏"]),
        Word(id: "robot",    text: "机器人", difficulty: .hard, aliases: ["robot", "機器人"]),
    ])
}
