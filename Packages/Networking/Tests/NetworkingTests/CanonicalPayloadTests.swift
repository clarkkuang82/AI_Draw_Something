import XCTest
@testable import Networking
import GameCore

/// The fixture below is also pinned in
/// `Worker/test/canonical_payload.test.ts`. If this test ever changes, that
/// one MUST be updated to match — the whole point is byte-for-byte parity
/// across iOS and TypeScript so App Attest signatures verify.
final class CanonicalPayloadTests: XCTestCase {
    func test_known_fixture_produces_pinned_bytes() throws {
        let payload = CanonicalGuessPayload(
            hintCategory: "cat",
            imageBase64: "/9j/AAAA",
            provider: .anthropic,
            roundId: "11111111-1111-1111-1111-111111111111",
            sessionId: "22222222-2222-2222-2222-222222222222"
        )
        let bytes = try payload.encodedBytes()
        let actual = String(data: bytes, encoding: .utf8)!
        XCTAssertEqual(actual, Self.expectedFixture)
    }

    func test_keys_are_alphabetical_regardless_of_init_order() throws {
        let p1 = CanonicalGuessPayload(
            hintCategory: "fish",
            imageBase64: "iVBORw0KGgo=",
            provider: .openai,
            roundId: "aaaa",
            sessionId: "bbbb"
        )
        let json = try String(data: p1.encodedBytes(), encoding: .utf8)!
        let keysOrder = json
            .components(separatedBy: ",")
            .compactMap { $0.split(separator: ":").first }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "{\"")) }
        XCTAssertEqual(keysOrder, ["hintCategory", "imageBase64", "provider", "roundId", "sessionId", "v"])
    }

    /// Pinned expected output — must equal the JS fixture in canonical_payload.test.ts.
    /// Forward slashes are NOT escaped on either side (Swift uses
    /// .withoutEscapingSlashes; JS JSON.stringify never escapes them).
    static let expectedFixture =
        "{\"hintCategory\":\"cat\",\"imageBase64\":\"/9j/AAAA\",\"provider\":\"anthropic\",\"roundId\":\"11111111-1111-1111-1111-111111111111\",\"sessionId\":\"22222222-2222-2222-2222-222222222222\",\"v\":1}"
}
