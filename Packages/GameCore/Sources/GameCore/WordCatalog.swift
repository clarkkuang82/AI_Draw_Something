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

    /// Hand-curated MVP seed list. Categories listed in
    /// `Drawing/Resources/sketches.json` (currently 20) can show up in
    /// AI-draws rounds; the rest are player-draws-only — the player still
    /// draws them with PencilKit and the VLM guesses.
    public static let mvpSeed: StaticWordCatalog = .init(words: [
        // — easy (20) —
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
        Word(id: "bird",     text: "鸟",   difficulty: .easy,   aliases: ["bird", "鳥", "小鸟"]),
        Word(id: "dog",      text: "狗",   difficulty: .easy,   aliases: ["dog", "puppy", "doggie", "狗狗"]),
        Word(id: "banana",   text: "香蕉", difficulty: .easy,   aliases: ["banana"]),
        Word(id: "key",      text: "钥匙", difficulty: .easy,   aliases: ["key", "鑰匙"]),
        Word(id: "balloon",  text: "气球", difficulty: .easy,   aliases: ["balloon", "氣球"]),
        Word(id: "cup",      text: "杯子", difficulty: .easy,   aliases: ["cup", "mug", "glass", "杯"]),
        Word(id: "egg",      text: "鸡蛋", difficulty: .easy,   aliases: ["egg", "雞蛋", "蛋"]),
        Word(id: "ball",     text: "球",   difficulty: .easy,   aliases: ["ball", "circle"]),
        Word(id: "leaf",     text: "叶子", difficulty: .easy,   aliases: ["leaf", "葉子"]),
        Word(id: "cloud",    text: "云",   difficulty: .easy,   aliases: ["cloud", "雲"]),
        // — medium (20) —
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
        Word(id: "candle",   text: "蜡烛", difficulty: .medium, aliases: ["candle", "蠟燭"]),
        Word(id: "scissors", text: "剪刀", difficulty: .medium, aliases: ["scissors"]),
        Word(id: "truck",    text: "卡车", difficulty: .medium, aliases: ["truck", "lorry", "卡車"]),
        Word(id: "fork",     text: "叉子", difficulty: .medium, aliases: ["fork"]),
        Word(id: "spoon",    text: "勺子", difficulty: .medium, aliases: ["spoon"]),
        Word(id: "ladder",   text: "梯子", difficulty: .medium, aliases: ["ladder"]),
        Word(id: "table",    text: "桌子", difficulty: .medium, aliases: ["table", "desk"]),
        Word(id: "ring",     text: "戒指", difficulty: .medium, aliases: ["ring"]),
        Word(id: "boat",     text: "船",   difficulty: .medium, aliases: ["boat", "ship", "船只"]),
        Word(id: "snake",    text: "蛇",   difficulty: .medium, aliases: ["snake", "serpent"]),
        // — hard (20) —
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
        Word(id: "rocket",   text: "火箭", difficulty: .hard,   aliases: ["rocket"]),
        Word(id: "octopus",  text: "章鱼", difficulty: .hard,   aliases: ["octopus", "章魚"]),
        Word(id: "lion",     text: "狮子", difficulty: .hard,   aliases: ["lion", "獅子"]),
        Word(id: "castle",   text: "城堡", difficulty: .hard,   aliases: ["castle"]),
        Word(id: "snail",    text: "蜗牛", difficulty: .hard,   aliases: ["snail", "蝸牛"]),
        Word(id: "windmill", text: "风车", difficulty: .hard,   aliases: ["windmill", "風車"]),
        Word(id: "lighthouse",text: "灯塔",difficulty: .hard,   aliases: ["lighthouse", "燈塔"]),
        Word(id: "cactus",   text: "仙人掌", difficulty: .hard, aliases: ["cactus"]),
        Word(id: "violin",   text: "小提琴", difficulty: .hard, aliases: ["violin", "fiddle"]),
        Word(id: "anchor",   text: "船锚", difficulty: .hard,   aliases: ["anchor", "船錨"]),
    ])
}
