import Foundation
import Observation

@Observable
@MainActor
public final class GameStore {
    public static let totalRounds = 6
    public static let aiDrawTimeLimit: TimeInterval = 60
    public static let playerDrawTimeLimit: TimeInterval = 45
    public static let defaultSkipBudget = 2

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
    /// JPEG of the most recently submitted player drawing. Populated by
    /// `submitPlayerDrawing(_:)`; the Reveal screen uses it to show what the
    /// player drew. Cleared at the start of every new round.
    public private(set) var lastPlayerDrawingJpeg: Data? = nil
    /// Consecutive correct rounds — feeds the streak multiplier.
    public private(set) var streak: Int = 0
    /// Skips remaining this game.
    public private(set) var skipsRemaining: Int = defaultSkipBudget
    /// Per-round audit log — used by the GameOver breakdown card and any
    /// future stats screen.
    public private(set) var roundHistory: [RoundResult] = []
    /// Points awarded by the most recent finishRound call. Lets the
    /// reveal screen animate a count-up from previous total.
    public private(set) var lastDelta: Int = 0
    /// Difficulty mode selected at startGame.
    public private(set) var difficultyMode: DifficultyMode = .standard
    /// Number of rounds the active game will play through.
    public private(set) var totalRoundsThisGame: Int = totalRounds
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

    /// Legacy zero-arg call kept for callers that don't care about config.
    public func startGame() {
        startGame(rounds: Self.totalRounds, mode: .standard)
    }

    public func startGame(rounds: Int, mode: DifficultyMode) {
        score = .zero
        roundIndex = 0
        usedWordIds = []
        currentGuessText = ""
        wrongGuessNonce = 0
        lastWrongGuess = nil
        streak = 0
        skipsRemaining = Self.defaultSkipBudget
        roundHistory = []
        lastDelta = 0
        difficultyMode = mode
        totalRoundsThisGame = max(1, rounds)
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

    /// User-initiated skip. Costs one skip from the budget. Acts as a
    /// timed-out outcome (zero points, breaks streak).
    public func requestSkip() {
        guard let round = phase.currentRound else { return }
        guard skipsRemaining > 0 else { return }
        skipsRemaining -= 1
        streamingTask?.cancel()
        streamingTask = nil
        finishRound(with: .skipped, round: round)
    }

    /// Timer expired during an AI-draws or player-draws round.
    public func handleTimeout() {
        guard let round = phase.currentRound else { return }
        streamingTask?.cancel()
        streamingTask = nil
        finishRound(with: .timedOut, round: round)
    }

    /// During `.playerDrawing`: drawing exported, send to model.
    public func submitPlayerDrawing(_ jpeg: Data) {
        guard case .playerDrawing(let round) = phase else { return }
        lastPlayerDrawingJpeg = jpeg
        streamingTask?.cancel()
        let provider = providerHint
        streamingTask = Task { [weak self, guesser] in
            guard let self else { return }
            // Watchdog: if no .final / .giveUp arrives within 35s
            // (e.g. flaky network, model hung), treat the round as
            // timed out so the UI doesn't sit forever on "等待 AI…".
            let watchdog = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 35 * 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if case .playerDrawing(let r) = self.phase {
                        self.currentGuessText = "(AI 没回应，按超时处理)"
                        self.streamingTask?.cancel()
                        self.finishRound(with: .timedOut, round: r)
                    }
                }
            }
            defer { watchdog.cancel() }
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
        let base = Scoring.award(outcome: outcome,
                                 difficulty: round.word.difficulty,
                                 timeLimit: limit)
        let isWin: Bool = {
            if case .correct = outcome { return true }
            return false
        }()
        // Streak: increments on a win, resets on miss/skip/timeout.
        let nextStreak = isWin ? streak + 1 : 0
        let multiplier = isWin ? Scoring.streakMultiplier(nextStreak) : 1.0
        let delta = Int((Double(base) * multiplier).rounded())
        streak = nextStreak
        lastDelta = delta
        score = Score(total: score.total + delta,
                      roundsCorrect: score.roundsCorrect + (isWin ? 1 : 0))
        roundHistory.append(.init(round: round, outcome: outcome,
                                  points: delta, multiplier: multiplier))
        phase = .reveal(round, outcome)
    }

    /// View calls this after the reveal animation has shown.
    public func acknowledgeReveal() {
        guard case .reveal(let round, _) = phase else { return }
        phase = .roundOver(round, score)
    }

    private func advanceToNextRound() {
        roundIndex += 1
        if roundIndex > totalRoundsThisGame {
            phase = .gameOver(score)
            return
        }
        let difficulty = difficultyForRound(roundIndex,
                                            mode: difficultyMode,
                                            total: totalRoundsThisGame)
        let kind: TurnKind = roundIndex.isMultiple(of: 2) ? .playerDraws : .aiDraws
        let restriction: Set<String>? = (kind == .aiDraws) ? aiDrawableIds : nil
        guard let word = catalog.pick(difficulty: difficulty,
                                      restrictedTo: restriction,
                                      excluding: usedWordIds) else {
            phase = .gameOver(score)
            return
        }
        lastWrongGuess = nil
        lastPlayerDrawingJpeg = nil
        usedWordIds.insert(word.id)
        let round = Round(index: roundIndex, kind: kind, word: word)
        phase = .showWord(round)
    }

    /// Maps round index → difficulty under the chosen mode. Splits the game
    /// into rough thirds (early easy, middle medium, late hard) for standard;
    /// shifts the curve up or down for hard / casual.
    private func difficultyForRound(_ idx: Int, mode: DifficultyMode, total: Int) -> Difficulty {
        let progress = Double(idx) / Double(max(total, 1))
        switch mode {
        case .casual:
            // 80% easy, 20% medium near end.
            return progress > 0.8 ? .medium : .easy
        case .standard:
            // Thirds: easy / medium / hard.
            if progress <= 1.0 / 3.0 { return .easy }
            if progress <= 2.0 / 3.0 { return .medium }
            return .hard
        case .hard:
            // 20% medium up front, 80% hard.
            return progress <= 0.2 ? .medium : .hard
        }
    }
}
