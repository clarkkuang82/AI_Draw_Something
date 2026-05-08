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
        Word(id: "cat",      text: "猫",   difficulty: .easy,   aliases: ["cat", "kitty", "kitten", "猫咪"], category: .animal),
        Word(id: "fish",     text: "鱼",   difficulty: .easy,   aliases: ["fish", "魚"], category: .animal),
        Word(id: "house",    text: "房子", difficulty: .easy,   aliases: ["house", "home", "屋", "房屋"], category: .object),
        Word(id: "apple",    text: "苹果", difficulty: .easy,   aliases: ["apple", "蘋果"], category: .food),
        Word(id: "sun",      text: "太阳", difficulty: .easy,   aliases: ["sun", "太陽"], category: .nature),
        Word(id: "moon",     text: "月亮", difficulty: .easy,   aliases: ["moon", "月"], category: .nature),
        Word(id: "star",     text: "星星", difficulty: .easy,   aliases: ["star", "星"], category: .nature),
        Word(id: "tree",     text: "树",   difficulty: .easy,   aliases: ["tree", "樹"], category: .nature),
        Word(id: "flower",   text: "花",   difficulty: .easy,   aliases: ["flower", "blossom"], category: .nature),
        Word(id: "heart",    text: "心",   difficulty: .easy,   aliases: ["heart", "love", "愛心"], category: .other),
        Word(id: "bird",     text: "鸟",   difficulty: .easy,   aliases: ["bird", "鳥", "小鸟"], category: .animal),
        Word(id: "dog",      text: "狗",   difficulty: .easy,   aliases: ["dog", "puppy", "doggie", "狗狗"], category: .animal),
        Word(id: "banana",   text: "香蕉", difficulty: .easy,   aliases: ["banana"], category: .food),
        Word(id: "key",      text: "钥匙", difficulty: .easy,   aliases: ["key", "鑰匙"], category: .object),
        Word(id: "balloon",  text: "气球", difficulty: .easy,   aliases: ["balloon", "氣球"], category: .object),
        Word(id: "cup",      text: "杯子", difficulty: .easy,   aliases: ["cup", "mug", "glass", "杯"], category: .object),
        Word(id: "egg",      text: "鸡蛋", difficulty: .easy,   aliases: ["egg", "雞蛋", "蛋"], category: .food),
        Word(id: "ball",     text: "球",   difficulty: .easy,   aliases: ["ball", "circle"], category: .object),
        Word(id: "leaf",     text: "叶子", difficulty: .easy,   aliases: ["leaf", "葉子"], category: .nature),
        Word(id: "cloud",    text: "云",   difficulty: .easy,   aliases: ["cloud", "雲"], category: .nature),
        // — medium (20) —
        Word(id: "airplane", text: "飞机", difficulty: .medium, aliases: ["airplane", "plane", "aircraft", "飛機"], category: .vehicle),
        Word(id: "umbrella", text: "雨伞", difficulty: .medium, aliases: ["umbrella", "雨傘", "伞"], category: .object),
        Word(id: "bicycle",  text: "自行车", difficulty: .medium, aliases: ["bicycle", "bike", "单车", "腳踏車"], category: .vehicle),
        Word(id: "car",      text: "汽车", difficulty: .medium, aliases: ["car", "auto", "automobile", "車"], category: .vehicle),
        Word(id: "clock",    text: "时钟", difficulty: .medium, aliases: ["clock", "watch", "钟", "鐘"], category: .object),
        Word(id: "glasses",  text: "眼镜", difficulty: .medium, aliases: ["glasses", "spectacles", "眼鏡"], category: .object),
        Word(id: "hat",      text: "帽子", difficulty: .medium, aliases: ["hat", "cap"], category: .object),
        Word(id: "shoe",     text: "鞋",   difficulty: .medium, aliases: ["shoe", "shoes", "鞋子"], category: .object),
        Word(id: "book",     text: "书",   difficulty: .medium, aliases: ["book", "書"], category: .object),
        Word(id: "chair",    text: "椅子", difficulty: .medium, aliases: ["chair", "seat"], category: .object),
        Word(id: "candle",   text: "蜡烛", difficulty: .medium, aliases: ["candle", "蠟燭"], category: .object),
        Word(id: "scissors", text: "剪刀", difficulty: .medium, aliases: ["scissors"], category: .object),
        Word(id: "truck",    text: "卡车", difficulty: .medium, aliases: ["truck", "lorry", "卡車"], category: .vehicle),
        Word(id: "fork",     text: "叉子", difficulty: .medium, aliases: ["fork"], category: .object),
        Word(id: "spoon",    text: "勺子", difficulty: .medium, aliases: ["spoon"], category: .object),
        Word(id: "ladder",   text: "梯子", difficulty: .medium, aliases: ["ladder"], category: .object),
        Word(id: "table",    text: "桌子", difficulty: .medium, aliases: ["table", "desk"], category: .object),
        Word(id: "ring",     text: "戒指", difficulty: .medium, aliases: ["ring"], category: .object),
        Word(id: "boat",     text: "船",   difficulty: .medium, aliases: ["boat", "ship", "船只"], category: .vehicle),
        Word(id: "snake",    text: "蛇",   difficulty: .medium, aliases: ["snake", "serpent"], category: .animal),
        // — hard (20) —
        Word(id: "guitar",   text: "吉他", difficulty: .hard,   aliases: ["guitar"], category: .object),
        Word(id: "piano",    text: "钢琴", difficulty: .hard,   aliases: ["piano", "鋼琴"], category: .object),
        Word(id: "butterfly",text: "蝴蝶", difficulty: .hard,   aliases: ["butterfly", "蝶"], category: .animal),
        Word(id: "giraffe",  text: "长颈鹿", difficulty: .hard, aliases: ["giraffe", "長頸鹿"], category: .animal),
        Word(id: "elephant", text: "大象", difficulty: .hard,   aliases: ["elephant"], category: .animal),
        Word(id: "dragon",   text: "龙",   difficulty: .hard,   aliases: ["dragon", "龍"], category: .animal),
        Word(id: "train",    text: "火车", difficulty: .hard,   aliases: ["train", "火車"], category: .vehicle),
        Word(id: "helicopter",text: "直升机", difficulty: .hard, aliases: ["helicopter", "chopper", "直升機"], category: .vehicle),
        Word(id: "kite",     text: "风筝", difficulty: .hard,   aliases: ["kite", "風箏"], category: .object),
        Word(id: "robot",    text: "机器人", difficulty: .hard, aliases: ["robot", "機器人"], category: .other),
        Word(id: "rocket",   text: "火箭", difficulty: .hard,   aliases: ["rocket"], category: .vehicle),
        Word(id: "octopus",  text: "章鱼", difficulty: .hard,   aliases: ["octopus", "章魚"], category: .animal),
        Word(id: "lion",     text: "狮子", difficulty: .hard,   aliases: ["lion", "獅子"], category: .animal),
        Word(id: "castle",   text: "城堡", difficulty: .hard,   aliases: ["castle"], category: .object),
        Word(id: "snail",    text: "蜗牛", difficulty: .hard,   aliases: ["snail", "蝸牛"], category: .animal),
        Word(id: "windmill", text: "风车", difficulty: .hard,   aliases: ["windmill", "風車"], category: .object),
        Word(id: "lighthouse",text: "灯塔",difficulty: .hard,   aliases: ["lighthouse", "燈塔"], category: .object),
        Word(id: "cactus",   text: "仙人掌", difficulty: .hard, aliases: ["cactus"], category: .nature),
        Word(id: "violin",   text: "小提琴", difficulty: .hard, aliases: ["violin", "fiddle"], category: .object),
        Word(id: "anchor",   text: "船锚", difficulty: .hard,   aliases: ["anchor", "船錨"], category: .object),
    ])
}
