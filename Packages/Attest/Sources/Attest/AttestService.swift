#if canImport(DeviceCheck)
import Foundation
import CryptoKit
import DeviceCheck
import Persistence

/// Wrapper around `DCAppAttestService` that handles:
///   - First-launch key generation + attestation registration with the Worker
///   - Per-request assertion generation against a canonical payload
///   - Persistence of `keyId` in Keychain
///
/// Production builds rely on this for *every* networked call. On unsupported
/// platforms (Simulator, Apple Silicon Mac, jailbroken device) the service
/// will refuse — `AttestConfig.devBypassSecret` provides a DEBUG-only escape
/// hatch that the Worker also has to be configured to accept.
public actor AttestService {
    public static let keychainService = "com.aidraw.attest"
    public static let keyIdKey = "keyId"

    private let config: AttestConfig
    private let nonceClient: NonceClient
    private let session: URLSession
    private let isSupportedOverride: Bool?
    private var cachedKeyId: String?

    public init(config: AttestConfig,
                nonceClient: NonceClient? = nil,
                session: URLSession = .shared,
                isSupportedOverride: Bool? = nil) {
        self.config = config
        self.nonceClient = nonceClient ?? NonceClient(config: config, session: session)
        self.session = session
        self.isSupportedOverride = isSupportedOverride
    }

    /// True if this device can do real App Attest. False on Simulator etc.
    public var isSupported: Bool {
        if let isSupportedOverride { return isSupportedOverride }
        return DCAppAttestService.shared.isSupported
    }

    /// Returns the persisted (or freshly generated + registered) keyId.
    public func ensureRegistered() async throws -> String {
        if let cached = cachedKeyId { return cached }
        if let stored = Keychain.get(Self.keyIdKey, service: Self.keychainService) {
            cachedKeyId = stored
            return stored
        }
        guard isSupported else {
            // Use a stable synthetic keyId so the dev-bypass + worker DEBUG path
            // can still deterministically map to an EntitlementDO.
            if config.devBypassSecret != nil {
                let synthetic = syntheticKeyId()
                try Keychain.set(synthetic, for: Self.keyIdKey, service: Self.keychainService)
                cachedKeyId = synthetic
                return synthetic
            }
            throw AttestError.unsupported
        }

        let svc = DCAppAttestService.shared
        let keyId = try await svc.generateKey()
        let challenge = try await nonceClient.fetch(.attest)
        let clientDataHash = SHA256.hash(data: challenge.valueBytes)
        let attestation = try await svc.attestKey(keyId, clientDataHash: Data(clientDataHash))

        try await registerWithWorker(keyId: keyId, attestation: attestation, challengeId: challenge.nonceId)
        try Keychain.set(keyId, for: Self.keyIdKey, service: Self.keychainService)
        cachedKeyId = keyId
        return keyId
    }

    /// Sign a payload + a fresh server nonce. Returns everything the Worker
    /// needs in the request's `attestation` field.
    public func signAssertion(payload: Data) async throws -> AttestationSignature {
        let keyId = try await ensureRegistered()

        if !isSupported, let secret = config.devBypassSecret {
            return AttestationSignature(
                keyId: keyId,
                assertionBase64: "",
                nonceId: "",
                devBypassHmac: hmacHex(secret: secret, msg: keyId)
            )
        }

        let nonce = try await nonceClient.fetch(.assert)
        var signed = Data()
        signed.append(payload)
        signed.append(nonce.valueBytes)
        let clientDataHash = SHA256.hash(data: signed)
        let assertion = try await DCAppAttestService.shared.generateAssertion(
            keyId, clientDataHash: Data(clientDataHash)
        )
        return AttestationSignature(
            keyId: keyId,
            assertionBase64: assertion.base64EncodedString(),
            nonceId: nonce.nonceId,
            devBypassHmac: nil
        )
    }

    // MARK: - private

    private func registerWithWorker(keyId: String, attestation: Data, challengeId: String) async throws {
        let url = config.workerBaseURL.appendingPathComponent("v1/attest/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "keyId": keyId,
            "attestationBase64": attestation.base64EncodedString(),
            "challengeId": challengeId,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AttestError.serverRejected(detail)
        }
    }

    private func syntheticKeyId() -> String {
        // 32 bytes of randomness, base64'd, deterministic-ish via a UUID.
        let uuid = UUID().uuidString
        return "dev-" + uuid.replacingOccurrences(of: "-", with: "")
    }

    private nonisolated func hmacHex(secret: String, msg: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

/// What the iOS app embeds in the request body's `attestation` field.
public struct AttestationSignature: Sendable {
    public let keyId: String
    public let assertionBase64: String
    public let nonceId: String
    /// DEBUG-only fallback when App Attest isn't supported. nil in production.
    public let devBypassHmac: String?

    public func bodyDict() -> [String: String] {
        [
            "keyId": keyId,
            "assertion": assertionBase64,
            "nonceId": nonceId,
        ]
    }
}
#endif
