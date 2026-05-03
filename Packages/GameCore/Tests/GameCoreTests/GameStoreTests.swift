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
