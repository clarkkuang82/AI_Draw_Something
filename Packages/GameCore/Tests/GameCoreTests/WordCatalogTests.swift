import XCTest
@testable import GameCore

final class WordCatalogTests: XCTestCase {
    func test_mvpSeed_has_words_in_each_difficulty_tier() {
        let cat = StaticWordCatalog.mvpSeed
        for tier in Difficulty.allCases {
            let count = cat.words.filter { $0.difficulty == tier }.count
            XCTAssertGreaterThan(count, 0, "no words for tier \(tier)")
        }
    }

    func test_pick_excludes_history() {
        let cat = StaticWordCatalog.mvpSeed
        var history: Set<String> = []
        for _ in 0..<3 {
            guard let w = cat.pick(difficulty: .easy, excluding: history) else {
                continue
            }
            XCTAssertFalse(history.contains(w.id))
            history.insert(w.id)
        }
    }

    func test_pick_falls_back_to_any_when_tier_exhausted() {
        let cat = StaticWordCatalog.mvpSeed
        // Exclude every easy word.
        let excludeAllEasy = Set(cat.words.filter { $0.difficulty == .easy }.map(\.id))
        let picked = cat.pick(difficulty: .easy, excluding: excludeAllEasy)
        XCTAssertNotNil(picked)
        // Fallback should pull from another tier (or nil if everything's gone).
        if let picked {
            XCTAssertNotEqual(picked.difficulty, .easy)
        }
    }

    func test_allCategoryIds_is_unique_and_sorted_by_caller() {
        let ids = StaticWordCatalog.mvpSeed.allCategoryIds
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate ids")
    }

    func test_pick_with_restrictedTo_only_returns_words_in_subset() {
        let cat = StaticWordCatalog.mvpSeed
        let allowed: Set<String> = ["cat", "fish", "house"]
        for _ in 0..<10 {
            let picked = cat.pick(difficulty: .easy, restrictedTo: allowed, excluding: [])
            XCTAssertNotNil(picked)
            if let picked { XCTAssertTrue(allowed.contains(picked.id), "got \(picked.id)") }
        }
    }

    func test_pick_with_empty_restrictedTo_falls_back_gracefully() {
        let cat = StaticWordCatalog.mvpSeed
        let picked = cat.pick(difficulty: .easy, restrictedTo: [], excluding: [])
        XCTAssertNil(picked, "empty allowed-set must produce no pick")
    }

    func test_word_matches_text_id_and_aliases_case_insensitive() {
        let cat = Word(id: "cat", text: "猫", difficulty: .easy, aliases: ["kitty", "猫咪"])
        XCTAssertTrue(cat.matches("猫"))
        XCTAssertTrue(cat.matches("Cat"))
        XCTAssertTrue(cat.matches("  CAT  "))
        XCTAssertTrue(cat.matches("kitty"))
        XCTAssertTrue(cat.matches("猫咪"))
        XCTAssertFalse(cat.matches("dog"))
        XCTAssertFalse(cat.matches(""))
    }
}
