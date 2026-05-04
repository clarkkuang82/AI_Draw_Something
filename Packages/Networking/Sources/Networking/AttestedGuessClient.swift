#if canImport(DeviceCheck)
import Foundation
import GameCore
import Attest

/// Production-path GuessClient. Talks to a Cloudflare Worker that holds
/// Anthropic / OpenAI keys, gated by App Attest. Drop-in replacement for
/// `DirectGuessClient` — both conform to `GuessClient`.
public struct AttestedGuessClient: GuessClient {
    public let workerBaseURL: URL
    public let attest: AttestService
    public let session: URLSession

    public init(workerBaseURL: URL, attest: AttestService, session: URLSession = .shared) {
        self.workerBaseURL = workerBaseURL
        self.attest = attest
        self.session = session
    }

    public func streamGuess(imageJpeg: Data,
                            hintCategoryId: String,
                            hintCategoryLabel: String,
                            provider: ProviderHint) -> AsyncThrowingStream<GuessEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try await buildBody(imageJpeg: imageJpeg,
                                                   hintCategoryId: hintCategoryId,
                                                   provider: provider)
                    let url = workerBaseURL.appendingPathComponent("v1/guess")
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let hmac = body.devBypassHmac {
                        req.setValue(hmac, forHTTPHeaderField: "X-Dev-Bypass")
                    }
                    req.httpBody = body.bytes

                    let stream = SSEStream.make(request: req, session: session)
                    for try await event in stream {
                        try Task.checkCancellation()
                        switch event.event {
                        case "guess":
                            if let text = decodeText(event.data) {
                                continuation.yield(.guess(text))
                            }
                        case "final":
                            if let guess = decodeFinalGuess(event.data) {
                                continuation.yield(.final(guess: guess))
                                continuation.finish()
                                return
                            }
                        case "giveUp":
                            continuation.yield(.giveUp)
                            continuation.finish()
                            return
                        case "error":
                            let msg = decodeErrorMessage(event.data) ?? "worker error"
                            continuation.finish(throwing: AttestError.serverRejected(msg))
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - request body

    private struct Body {
        let bytes: Data
        let devBypassHmac: String?
    }

    private func buildBody(imageJpeg: Data,
                           hintCategoryId: String,
                           provider: ProviderHint) async throws -> Body {
        let payload = CanonicalGuessPayload(
            hintCategory: hintCategoryId,
            imageBase64: imageJpeg.base64EncodedString(),
            provider: provider,
            roundId: UUID().uuidString.lowercased(),
            sessionId: UUID().uuidString.lowercased()
        )
        let payloadBytes = try payload.encodedBytes()
        let signature = try await attest.signAssertion(payload: payloadBytes)

        // On-the-wire body: payload fields + attestation. sortedKeys handles
        // ordering. The Worker reconstructs canonical bytes by stripping the
        // attestation field and re-encoding alphabetically — so we must
        // produce identical key/value pairs for the canonical fields.
        var dict: [String: Any] = [
            "v": payload.v,
            "sessionId": payload.sessionId,
            "roundId": payload.roundId,
            "hintCategory": payload.hintCategory,
            "provider": payload.provider,
            "imageBase64": payload.imageBase64,
            "attestation": signature.bodyDict(),
        ]
        if signature.devBypassHmac == nil, signature.assertionBase64.isEmpty {
            dict["attestation"] = ["keyId": signature.keyId, "assertion": "", "nonceId": ""]
        }

        let bodyBytes = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return Body(bytes: bodyBytes, devBypassHmac: signature.devBypassHmac)
    }
}

// MARK: - SSE event payload decoders

private func decodeText(_ data: String) -> String? {
    guard let raw = data.data(using: .utf8) else { return nil }
    let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
    return obj?["text"] as? String
}

private func decodeFinalGuess(_ data: String) -> String? {
    guard let raw = data.data(using: .utf8) else { return nil }
    let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
    return obj?["guess"] as? String
}

private func decodeErrorMessage(_ data: String) -> String? {
    guard let raw = data.data(using: .utf8) else { return nil }
    let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
    return obj?["message"] as? String
}
#endif
