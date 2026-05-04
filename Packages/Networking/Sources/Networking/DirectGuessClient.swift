import Foundation
import GameCore

/// MVP-only client that talks to Anthropic / OpenAI directly using a key the
/// user pasted into the settings sheet (stored in Keychain).
///
/// **Security note**: this is the BYOK path. There is no prompt-shape lock,
/// no rate limit, no spend cap — the user is paying their own bill. Production
/// builds will swap this out for `AttestedGuessClient` (Worker-fronted).
public struct DirectGuessClient: GuessClient {
    public typealias KeyResolver = @Sendable (ProviderHint) -> String?

    public let keyResolver: KeyResolver
    public let session: URLSession

    public init(keyResolver: @escaping KeyResolver,
                session: URLSession = .shared) {
        self.keyResolver = keyResolver
        self.session = session
    }

    public func streamGuess(imageJpeg: Data,
                            hintCategoryId: String,
                            hintCategoryLabel: String,
                            provider: ProviderHint) -> AsyncThrowingStream<GuessEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = keyResolver(provider) else {
                        throw GuessClientError.missingKey(provider)
                    }
                    switch provider {
                    case .anthropic:
                        try await streamAnthropic(key: key,
                                                  imageJpeg: imageJpeg,
                                                  continuation: continuation)
                    case .openai:
                        try await streamOpenAI(key: key,
                                               imageJpeg: imageJpeg,
                                               continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Prompt

    /// The locked prompt shape. Note: we deliberately do NOT include the
    /// answer category — the MVP wants the model to actually identify, not
    /// confirm. v2 may include 4 distractors as a closed candidate set.
    private static let systemPrompt = """
    你在玩看图猜词。仅按以下两种格式之一输出，每次只回一行，不超过 8 个汉字，
    不解释、不寒暄、不复述提示：
      猜测时：「是不是 X？」
      确信时：「我猜到了：X！」
    最多 3 次猜测，超过即输出「我猜不出来」。
    每行一个猜测，按顺序从最可能到最不可能。
    """

    // MARK: - Anthropic

    private func streamAnthropic(key: String,
                                 imageJpeg: Data,
                                 continuation: AsyncThrowingStream<GuessEvent, Error>.Continuation) async throws {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 80,
            "stream": true,
            "system": Self.systemPrompt,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": imageJpeg.base64EncodedString()
                        ]
                    ],
                    ["type": "text", "text": "请猜。"]
                ]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var parser = GuessParser()
        let stream = SSEStream.make(request: req, session: session)
        for try await event in stream {
            try Task.checkCancellation()
            // Anthropic uses event: content_block_delta with JSON in data:
            guard event.event == "content_block_delta" else { continue }
            guard let data = event.data.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = obj["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { continue }
            for evt in parser.ingest(text) {
                continuation.yield(evt)
                if case .final = evt { return }
                if case .giveUp = evt { return }
            }
        }
        for evt in parser.flush() {
            continuation.yield(evt)
        }
    }

    // MARK: - OpenAI

    private func streamOpenAI(key: String,
                              imageJpeg: Data,
                              continuation: AsyncThrowingStream<GuessEvent, Error>.Continuation) async throws {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")

        let imageURL = "data:image/jpeg;base64,\(imageJpeg.base64EncodedString())"
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 80,
            "stream": true,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "请猜。"],
                    ["type": "image_url",
                     "image_url": ["url": imageURL]]
                ]]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var parser = GuessParser()
        let stream = SSEStream.make(request: req, session: session)
        for try await event in stream {
            try Task.checkCancellation()
            // OpenAI emits raw `data: {...}` chunks, no event: line; ends with `data: [DONE]`
            let payload = event.data
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String else { continue }
            for evt in parser.ingest(text) {
                continuation.yield(evt)
                if case .final = evt { return }
                if case .giveUp = evt { return }
            }
        }
        for evt in parser.flush() {
            continuation.yield(evt)
        }
    }
}

public enum GuessClientError: LocalizedError {
    case missingKey(ProviderHint)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let p):
            return "请在设置里填入 \(p == .anthropic ? "Anthropic" : "OpenAI") API Key"
        }
    }
}
