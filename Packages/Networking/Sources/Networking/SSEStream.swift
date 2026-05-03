import Foundation

public struct SSEEvent: Sendable, Equatable {
    public let event: String?
    public let data: String
}

public enum SSEError: Error {
    case httpStatus(Int, String)
    case malformed
}

/// Thin wrapper that converts an `URLSession` byte stream into an
/// AsyncThrowingStream of parsed SSE events.
public enum SSEStream {
    public static func make(request: URLRequest,
                            session: URLSession = .shared) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line + "\n"
                            if body.count > 4_000 { break }
                        }
                        throw SSEError.httpStatus(http.statusCode, body)
                    }

                    var bufferEvent: String? = nil
                    var bufferData: [String] = []

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty {
                            if !bufferData.isEmpty || bufferEvent != nil {
                                continuation.yield(SSEEvent(
                                    event: bufferEvent,
                                    data: bufferData.joined(separator: "\n")))
                                bufferEvent = nil
                                bufferData = []
                            }
                            continue
                        }
                        if line.hasPrefix("event:") {
                            bufferEvent = String(line.dropFirst("event:".count))
                                .trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            bufferData.append(String(line.dropFirst("data:".count))
                                .trimmingCharacters(in: .whitespaces))
                        }
                        // ignore comments and other field types
                    }

                    if !bufferData.isEmpty || bufferEvent != nil {
                        continuation.yield(SSEEvent(
                            event: bufferEvent,
                            data: bufferData.joined(separator: "\n")))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
