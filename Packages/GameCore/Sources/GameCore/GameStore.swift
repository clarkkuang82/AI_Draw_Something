import Foundation
import Observation

@Observable
@MainActor
public final class GameStore {
    public static let totalRounds = 6
    public static let aiDrawTimeLimit: TimeInterval = 60
    public static let playerDrawTimeLimit: TimeInterval = 45

    public private(set) var phase: GamePhase = .idle
    public private(set) var score: Score = .zero
    public private(set) var roundIndex: Int = 0
    /// Latest interim guess text from the VLM, displayed during `.playerDrawing`.
    public private(set) var currentGuessText: String = ""
    /// Increments every time the player submits a wrong guess during an
    /// AI-draws round. Views observe this to flash a "not quite" hint.
    public private(set) var wrongGuessNonce: Int = 0
    /// The most recent rejected guess text. Cleared on round transitions.
    public private(set) var lastWrongGuess: String? = nil
    /// Provider currently selected by the user (mirrors UserDefaults).
    public var providerHint: ProviderHint = .anthropic

    private let catalog: any WordCatalog
    private let guesser: any GuessClient
    /// Subset of category ids that have sketches available for AI-draws
    /// rounds. `nil` means no restriction (every word is playable as
    /// AI-draws). Player-draws rounds always use the full catalog.
    private let aiDrawableIds: Set<String>?
    private var usedWordIds: Set<String> = []
    private var roundStartedAt: Date?
    private var streamingTask: Task<Void, Never>?

    public init(catalog: any WordCatalog,
                guesser: any GuessClient,
                aiDrawableIds: Set<String>? = nil) {
        self.catalog = catalog
        self.guesser = guesser
        self.aiDrawableIds = aiDrawableIds
    }

    // MARK: - Public actions

    public func startGame() {
        score = .zero
        roundIndex = 0
        usedWordIds = []
        currentGuessText = ""
        wrongGuessNonce = 0
        lastWrongGuess = nil
        phase = .loading
        advanceToNextRound()
    }

    /// User taps "begin" on the show-word screen.
    public func beginRound() {
        guard case .showWord(let round) = phase else { return }
        roundStartedAt = .now
        currentGuessText = ""
        switch round.kind {
        case .aiDraws:    phase = .aiDrawing(round)
        case .playerDraws: phase = .playerDrawing(round)
        }
    }

    /// During `.aiDrawing`: player types a guess. Fuzzy-matches against the
    /// answer (text + English id + aliases), case-insensitive.
    public func submitPlayerGuess(_ text: String) {
        guard case .aiDrawing(let round) = phase else { return }
        if round.word.matches(text) {
            lastWrongGuess = nil
            finishRound(with: .correct(elapsed: elapsed()), round: round)
        } else {
            lastWrongGuess = text.trimmingCharacters(in: .whitespacesAndNewlines)
            wrongGuessNonce &+= 1
        }
    }

    /// During `.aiDrawing` or `.playerDrawing`: timer expired.
    public func handleTimeout() {
        guard let round = phase.currentRound else { return }
        streamingTask?.cancel()
        streamingTask = nil
        finishRound(with: .timedOut, round: round)
    }

    /// During `.playerDrawing`: drawing exported, send to model.
    public func submitPlayerDrawing(_ jpeg: Data) {
        guard case .playerDrawing(let round) = phase else { return }
        streamingTask?.cancel()
        let provider = providerHint
        streamingTask = Task { [weak self, guesser] in
            guard let self else { return }
            do {
                let stream = guesser.streamGuess(
                    imageJpeg: jpeg,
                    hintCategoryId: round.word.id,
                    hintCategoryLabel: round.word.text,
                    provider: provider
                )
                for try await event in stream {
                    if Task.isCancelled { return }
                    self.apply(event, in: round)
                    if case .final = event { return }
                    if case .giveUp = event { return }
                }
            } catch {
                if !Task.isCancelled {
                    self.currentGuessText = "(网络出错：\(error.localizedDescription))"
                }
            }
        }
    }

    public func nextRound() {
        advanceToNextRound()
    }

    public func abandon() {
        streamingTask?.cancel()
        streamingTask = nil
        phase = .gameOver(score)
    }

    // MARK: - Internals

    private func apply(_ event: GuessEvent, in round: Round) {
        switch event {
        case .guess(let text):
            currentGuessText = text
        case .final(let guess):
            currentGuessText = guess
            let isCorrect = guess == round.word.text
            finishRound(with: isCorrect ? .correct(elapsed: elapsed()) : .timedOut,
                        round: round)
        case .giveUp:
            finishRound(with: .timedOut, round: round)
        }
    }

    private func elapsed() -> TimeInterval {
        guard let start = roundStartedAt else { return 0 }
        return Date.now.timeIntervalSince(start)
    }

    private func finishRound(with outcome: Outcome, round: Round) {
        let limit = round.kind == .aiDraws
            ? Self.aiDrawTimeLimit
            : Self.playerDrawTimeLimit
        let delta = Scoring.award(outcome: outcome,
                                  difficulty: round.word.difficulty,
                                  timeLimit: limit)
        score = Score(total: score.total + delta,
                      roundsCorrect: score.roundsCorrect + (delta > 0 ? 1 : 0))
        phase = .reveal(round, outcome)
    }

    /// View calls this after the reveal animation has shown.
    public func acknowledgeReveal() {
        guard case .reveal(let round, _) = phase else { return }
        phase = .roundOver(round, score)
    }

    private func advanceToNextRound() {
        roundIndex += 1
        if roundIndex > Self.totalRounds {
            phase = .gameOver(score)
            return
        }
        // Difficulty curve: rounds 1-2 easy, 3-4 medium, 5-6 hard.
        let difficulty: Difficulty = roundIndex <= 2 ? .easy
            : roundIndex <= 4 ? .medium : .hard
        let kind: TurnKind = roundIndex.isMultiple(of: 2) ? .playerDraws : .aiDraws
        let restriction: Set<String>? = (kind == .aiDraws) ? aiDrawableIds : nil
        guard let word = catalog.pick(difficulty: difficulty,
                                      restrictedTo: restriction,
                                      excluding: usedWordIds) else {
            phase = .gameOver(score)
            return
        }
        lastWrongGuess = nil
        usedWordIds.insert(word.id)
        let round = Round(index: roundIndex, kind: kind, word: word)
        phase = .showWord(round)
    }
}
