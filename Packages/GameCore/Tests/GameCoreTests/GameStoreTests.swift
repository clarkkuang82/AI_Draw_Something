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
