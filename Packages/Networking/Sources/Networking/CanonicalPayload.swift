import Foundation
import GameCore

/// The exact bytes signed by App Attest assertions for /v1/guess.
/// Lives in its own module-public type so tests can pin its output and
/// guarantee byte-for-byte compatibility with the Worker's
/// `canonicalPayloadBytes`.
public struct CanonicalGuessPayload: Encodable, Sendable {
    public let hintCategory: String
    public let imageBase64: String
    public let provider: String
    public let roundId: String
    public let sessionId: String
    public let v: Int

    public init(hintCategory: String,
                imageBase64: String,
                provider: ProviderHint,
                roundId: String,
                sessionId: String,
                v: Int = 1) {
        self.hintCategory = hintCategory
        self.imageBase64 = imageBase64
        self.provider = provider.rawValue
        self.roundId = roundId
        self.sessionId = sessionId
        self.v = v
    }

    public func encodedBytes() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
