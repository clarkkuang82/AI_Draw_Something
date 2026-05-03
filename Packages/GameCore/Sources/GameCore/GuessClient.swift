import Foundation

public enum ProviderHint: String, Sendable, Codable {
    case anthropic
    case openai
}

public enum GuessEvent: Sendable, Equatable {
    /// AI emitted an interim guess like "是不是 飞机?".
    case guess(String)
    /// AI claims it has identified the drawing. GameStore matches against
    /// the round's correct answer to decide outcome.
    case final(guess: String)
    /// Model gave up.
    case giveUp
}

public protocol GuessClient: Sendable {
    /// Stream interim and final guesses for `imageJpeg`.
    /// - hintCategoryId: canonical id (e.g. "cat"). Used for closed-enum
    ///   validation server-side.
    /// - hintCategoryLabel: localized display text (e.g. "猫"). Plugged into
    ///   the system prompt so the model knows the candidate set.
    func streamGuess(imageJpeg: Data,
                     hintCategoryId: String,
                     hintCategoryLabel: String,
                     provider: ProviderHint) -> AsyncThrowingStream<GuessEvent, Error>
}
