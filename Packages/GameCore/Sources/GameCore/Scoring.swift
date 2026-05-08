import Foundation

public struct Score: Sendable, Hashable, Codable {
    public var total: Int
    public var roundsCorrect: Int

    public static let zero = Score(total: 0, roundsCorrect: 0)

    public init(total: Int, roundsCorrect: Int) {
        self.total = total
        self.roundsCorrect = roundsCorrect
    }
}

public enum Scoring {
    /// Award points based on time-to-correct and difficulty.
    /// - Easy: 100 base; Medium: 200; Hard: 300
    /// - Timing bonus: linear from full base at t=0 down to 30% at the time limit
    public static func award(outcome: Outcome,
                             difficulty: Difficulty,
                             timeLimit: TimeInterval) -> Int {
        switch outcome {
        case .timedOut, .skipped:
            return 0
        case .correct(let elapsed):
            let base: Int = {
                switch difficulty {
                case .easy:   return 100
                case .medium: return 200
                case .hard:   return 300
                }
            }()
            let ratio = max(0.3, 1.0 - 0.7 * (elapsed / max(1, timeLimit)))
            return Int((Double(base) * ratio).rounded())
        }
    }

    /// Streak bonus multiplier — encourages chain-correct answers.
    /// Streak counts only consecutive correct rounds; resets on
    /// timeout / skip / wrong-final.
    /// - 0–1 correct in a row: 1.0× (no bonus)
    /// - 2 in a row: 1.25×
    /// - 3 in a row: 1.5×
    /// - 4+ in a row: 1.75× (capped)
    public static func streakMultiplier(_ streak: Int) -> Double {
        switch streak {
        case ...1: return 1.0
        case 2:    return 1.25
        case 3:    return 1.5
        default:   return 1.75
        }
    }
}
