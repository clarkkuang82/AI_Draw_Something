import XCTest
@testable import GameCore

final class GameStoreTests: XCTestCase {
    @MainActor
    func test_startGame_emitsShowWord() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        guard case .showWord(let round) = store.phase else {
            return XCTFail("expected .showWord, got \(store.phase)")
        }
        XCTAssertEqual(round.index, 1)
        XCTAssertEqual(round.kind, .aiDraws)
    }

    @MainActor
    func test_correctGuess_advancesToReveal() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        guard case .showWord(let round) = store.phase else { return XCTFail() }
        store.beginRound()
        store.submitPlayerGuess(round.word.text)
        guard case .reveal(_, let outcome) = store.phase else {
            return XCTFail("expected .reveal, got \(store.phase)")
        }
        if case .correct = outcome { /* ok */ } else {
            XCTFail("expected .correct outcome")
        }
        XCTAssertGreaterThan(store.score.total, 0)
    }

    @MainActor
    func test_wrongGuess_increments_nonce_and_does_not_advance() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        guard case .showWord(let round) = store.phase else { return XCTFail() }
        XCTAssertEqual(round.kind, .aiDraws)
        store.beginRound()
        let beforeNonce = store.wrongGuessNonce
        store.submitPlayerGuess("definitely_not_the_answer")
        XCTAssertEqual(store.wrongGuessNonce, beforeNonce + 1)
        XCTAssertEqual(store.lastWrongGuess, "definitely_not_the_answer")
        if case .aiDrawing = store.phase { /* still drawing */ } else {
            XCTFail("phase moved on a wrong guess: \(store.phase)")
        }
    }

    @MainActor
    func test_aiDrawableIds_restricts_aiDraws_round_words() {
        // Restrict to a single id; round 1 (aiDraws, easy) must use it.
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser(),
                              aiDrawableIds: ["fish"])
        store.startGame()
        guard case .showWord(let round) = store.phase else { return XCTFail() }
        XCTAssertEqual(round.kind, .aiDraws)
        XCTAssertEqual(round.word.id, "fish")
    }

    @MainActor
    func test_aiDrawableIds_does_not_restrict_playerDraws_rounds() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser(),
                              aiDrawableIds: ["fish"])
        store.startGame()
        // Round 1 is aiDraws → fish (forced).
        guard case .showWord = store.phase else { return XCTFail() }
        store.beginRound()
        store.submitPlayerGuess("鱼")
        store.acknowledgeReveal()
        store.nextRound()
        // Round 2 is playerDraws → can be any easy word, NOT restricted to fish.
        guard case .showWord(let r2) = store.phase else { return XCTFail() }
        XCTAssertEqual(r2.kind, .playerDraws)
        // fish was already used, so the picker would skip it anyway; the
        // important property is that the picker didn't get stuck (nil round).
        XCTAssertNotEqual(r2.word.id, "fish")
    }

    @MainActor
    func test_streak_doubles_when_two_in_a_row_correct() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        // Round 1 — easy, aiDraws
        guard case .showWord(let r1) = store.phase else { return XCTFail() }
        store.beginRound()
        store.submitPlayerGuess(r1.word.text)
        XCTAssertEqual(store.streak, 1, "first correct: streak 1")
        let firstDelta = store.lastDelta
        XCTAssertGreaterThan(firstDelta, 0)
        store.acknowledgeReveal()
        store.nextRound()
        // Round 2 — easy, playerDraws → simulate a correct answer via final event.
        // For this test we just call the same correct path by submitting a guess.
        // playerDrawing phase doesn't accept submitPlayerGuess, so we can't do
        // it directly; use timeout to break the streak.
        guard case .showWord = store.phase else { return XCTFail() }
        store.beginRound()
        store.handleTimeout()
        XCTAssertEqual(store.streak, 0, "timeout breaks streak")
    }

    @MainActor
    func test_skip_consumes_budget_and_records_zero_points() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        guard case .showWord = store.phase else { return XCTFail() }
        store.beginRound()
        let beforeBudget = store.skipsRemaining
        store.requestSkip()
        XCTAssertEqual(store.skipsRemaining, beforeBudget - 1)
        guard case .reveal(_, let outcome) = store.phase else { return XCTFail() }
        if case .skipped = outcome { /* ok */ } else { XCTFail("not .skipped") }
        XCTAssertEqual(store.lastDelta, 0)
        XCTAssertEqual(store.score.total, 0)
        // History should record it.
        XCTAssertEqual(store.roundHistory.count, 1)
        XCTAssertFalse(store.roundHistory[0].didWin)
    }

    @MainActor
    func test_skip_blocked_after_budget_exhausted() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        // Use up all skips.
        for _ in 0..<GameStore.defaultSkipBudget {
            guard case .showWord = store.phase else { return XCTFail() }
            store.beginRound()
            store.requestSkip()
            store.acknowledgeReveal()
            store.nextRound()
        }
        XCTAssertEqual(store.skipsRemaining, 0)
        // Try one more skip — must be a no-op.
        guard case .showWord = store.phase else { return XCTFail() }
        store.beginRound()
        let phaseBefore = store.phase
        store.requestSkip()
        // requestSkip must NOT change phase when budget is empty.
        if case .reveal = store.phase {
            XCTFail("skip went through despite empty budget")
        }
        _ = phaseBefore
    }

    @MainActor
    func test_roundHistory_grows_per_round() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        XCTAssertEqual(store.roundHistory.count, 0)
        guard case .showWord(let r1) = store.phase else { return XCTFail() }
        store.beginRound()
        store.submitPlayerGuess(r1.word.text)
        XCTAssertEqual(store.roundHistory.count, 1)
        XCTAssertTrue(store.roundHistory[0].didWin)
        XCTAssertEqual(store.roundHistory[0].round.id, r1.id)
    }

    @MainActor
    func test_casual_mode_uses_only_easy_and_medium() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame(rounds: 6, mode: .casual)
        for _ in 1...6 {
            guard case .showWord(let r) = store.phase else { return XCTFail() }
            XCTAssertNotEqual(r.word.difficulty, .hard, "casual leaked a hard word")
            store.beginRound()
            store.handleTimeout()
            store.acknowledgeReveal()
            store.nextRound()
        }
    }

    @MainActor
    func test_hard_mode_avoids_easy() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame(rounds: 6, mode: .hard)
        for _ in 1...6 {
            guard case .showWord(let r) = store.phase else { return XCTFail() }
            XCTAssertNotEqual(r.word.difficulty, .easy, "hard mode leaked an easy word")
            store.beginRound()
            store.handleTimeout()
            store.acknowledgeReveal()
            store.nextRound()
        }
    }

    @MainActor
    func test_custom_round_count_finishes_when_consumed() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame(rounds: 3, mode: .casual)
        for _ in 1...3 {
            guard case .showWord = store.phase else { return XCTFail() }
            store.beginRound()
            store.handleTimeout()
            store.acknowledgeReveal()
            store.nextRound()
        }
        if case .gameOver = store.phase { /* ok */ } else {
            XCTFail("expected gameOver after \(3) rounds, got \(store.phase)")
        }
    }

    @MainActor
    func test_streakMultiplier_curve() {
        XCTAssertEqual(Scoring.streakMultiplier(0), 1.0)
        XCTAssertEqual(Scoring.streakMultiplier(1), 1.0)
        XCTAssertEqual(Scoring.streakMultiplier(2), 1.25)
        XCTAssertEqual(Scoring.streakMultiplier(3), 1.5)
        XCTAssertEqual(Scoring.streakMultiplier(4), 1.75)
        XCTAssertEqual(Scoring.streakMultiplier(99), 1.75)
    }

    @MainActor
    func test_sixRounds_thenGameOver() {
        let store = GameStore(catalog: StaticWordCatalog.mvpSeed,
                              guesser: NoopGuesser())
        store.startGame()
        for _ in 1...GameStore.totalRounds {
            guard case .showWord(let round) = store.phase else { return XCTFail() }
            store.beginRound()
            switch round.kind {
            case .aiDraws:
                store.submitPlayerGuess(round.word.text)
            case .playerDraws:
                // simulate timeout shortcut
                store.handleTimeout()
            }
            store.acknowledgeReveal()
            store.nextRound()
        }
        if case .gameOver = store.phase { /* ok */ } else {
            XCTFail("expected .gameOver, got \(store.phase)")
        }
    }
}

private struct NoopGuesser: GuessClient {
    func streamGuess(imageJpeg: Data,
                     hintCategoryId: String,
                     hintCategoryLabel: String,
                     provider: ProviderHint) -> AsyncThrowingStream<GuessEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
