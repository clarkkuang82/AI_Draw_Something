import XCTest
@testable import Networking
import GameCore

/// Mirrors `Worker/test/parser.test.ts`. If a behavior diverges between the
/// iOS-side parser (used in BYOK / DirectGuessClient) and the Worker-side
/// parser (used in the production path), the same drawing will yield
/// different events depending on routing — disastrous for scoring.
final class GuessParserTests: XCTestCase {
    func test_guess_event_on_complete_line() {
        var p = GuessParser()
        let events = p.ingest("是不是 飞机？\n")
        XCTAssertEqual(events, [.guess("飞机")])
    }

    func test_accepts_ascii_question_mark() {
        var p = GuessParser()
        XCTAssertEqual(p.ingest("是不是 房子?\n"), [.guess("房子")])
    }

    func test_dedupes_consecutive_identical_guesses() {
        var p = GuessParser()
        _ = p.ingest("是不是 猫?\n")
        XCTAssertEqual(p.ingest("是不是 猫?\n"), [])
    }

    func test_emits_final_on_claim() {
        var p = GuessParser()
        XCTAssertEqual(p.ingest("我猜到了：吉他！\n"), [.final(guess: "吉他")])
    }

    func test_handles_partial_buffer_ending_with_question_mark() {
        var p = GuessParser()
        XCTAssertEqual(p.ingest("是不是 鱼？"), [.guess("鱼")])
    }

    func test_emits_giveUp_on_marker_line() {
        var p = GuessParser()
        XCTAssertEqual(p.ingest("我猜不出来\n"), [.giveUp])
    }

    func test_ignores_stray_text() {
        var p = GuessParser()
        XCTAssertEqual(p.ingest("hello world\n"), [])
    }

    func test_flush_after_partial_already_fired() {
        var p = GuessParser()
        _ = p.ingest("是不是")
        _ = p.ingest(" 雨伞？")
        XCTAssertEqual(p.flush(), [])
    }

    func test_split_mid_word_across_deltas() {
        var p = GuessParser()
        XCTAssertEqual(p.ingest("是不是"), [])
        XCTAssertEqual(p.ingest(" 飞机？\n是不是"), [.guess("飞机")])
        XCTAssertEqual(p.ingest(" 鱼？\n"), [.guess("鱼")])
    }
}
