import Foundation

public enum GamePhase: Equatable, Sendable {
    case idle
    case loading
    case showWord(Round)
    case aiDrawing(Round)
    case playerDrawing(Round)
    case reveal(Round, Outcome)
    case roundOver(Round, Score)
    case gameOver(Score)
}

extension GamePhase {
    public var currentRound: Round? {
        switch self {
        case .showWord(let r), .aiDrawing(let r), .playerDrawing(let r):
            return r
        case .reveal(let r, _), .roundOver(let r, _):
            return r
        case .idle, .loading, .gameOver:
            return nil
        }
    }
}
