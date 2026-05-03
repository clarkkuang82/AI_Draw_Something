import XCTest
@testable import GameCore

final class ScoringTests: XCTestCase {
    func test_award_for_correct_easy_at_zero_time_is_full_base() {
        let pts = Scoring.award(outcome: .correct(elapsed: 0),
                                difficulty: .easy,
                                timeLimit: 60)
        XCTAssertEqual(pts, 100)
    }

    func test_award_decays_to_thirty_percent_at_time_limit() {
        let pts = Scoring.award(outcome: .correct(elapsed: 60),
                                difficulty: .medium,
                                timeLimit: 60)
        // 30% of 200 = 60
        XCTAssertEqual(pts, 60)
    }

    func test_award_does_not_go_below_thirty_percent() {
        let pts = Scoring.award(outcome: .correct(elapsed: 9999),
                                difficulty: .hard,
                                timeLimit: 60)
        // 30% of 300 = 90
        XCTAssertEqual(pts, 90)
    }

    func test_timeOut_yields_zero() {
        XCTAssertEqual(Scoring.award(outcome: .timedOut,
                                     difficulty: .hard,
                                     timeLimit: 60), 0)
    }

    func test_skipped_yields_zero() {
        XCTAssertEqual(Scoring.award(outcome: .skipped,
                                     difficulty: .hard,
                                     timeLimit: 60), 0)
    }

    func test_difficulty_bases_are_distinct() {
        let easy = Scoring.award(outcome: .correct(elapsed: 0), difficulty: .easy, timeLimit: 60)
        let med  = Scoring.award(outcome: .correct(elapsed: 0), difficulty: .medium, timeLimit: 60)
        let hard = Scoring.award(outcome: .correct(elapsed: 0), difficulty: .hard, timeLimit: 60)
        XCTAssertEqual(easy, 100)
        XCTAssertEqual(med, 200)
        XCTAssertEqual(hard, 300)
    }
}
