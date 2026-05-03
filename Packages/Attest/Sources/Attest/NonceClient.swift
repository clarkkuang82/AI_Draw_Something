import Foundation

public enum NoncePurpose: String, Sendable, Codable {
    case attest, assert
}

public struct ServerNonce: Sendable, Codable {
    public let nonceId: String
    public let value: String        // hex
    public let expiresAt: TimeInterval

    public var valueBytes: Data { Data(hex: value) ?? Data() }
}

public actor NonceClient {
    private let config: AttestConfig
    private let session: URLSession

    public init(config: AttestConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func fetch(_ purpose: NoncePurpose) async throws -> ServerNonce {
        let url = config.workerBaseURL.appendingPathComponent("v1/nonce")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["purpose": purpose.rawValue])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AttestError.network("nonce status \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONDecoder().decode(ServerNonce.self, from: data)
    }
}

public enum AttestError: Error, LocalizedError {
    case network(String)
    case unsupported
    case keyMissing
    case serverRejected(String)

    public var errorDescription: String? {
        switch self {
        case .network(let s): return "network: \(s)"
        case .unsupported:    return "App Attest unsupported on this device"
        case .keyMissing:     return "App Attest key missing"
        case .serverRejected(let s): return "server rejected: \(s)"
        }
    }
}

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var idx = hex.startIndex
        for _ in 0..<len {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}
