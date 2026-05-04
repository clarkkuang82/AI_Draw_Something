import Foundation
import Attest

/// Mirror of EntitlementDO state — used by the iOS UI to render the HUD
/// counter and decide whether to show paywall before /v1/guess fires.
public struct Entitlement: Sendable, Codable, Equatable {
    public let freeUsedToday: Int
    public let day: String
    public let paidCredits: Int
    public let subscriptionExpiresAt: Date?
    public let referralCode: String?
    public let referredBy: String?
    public let referralsConsumed: Int

    public var isSubscriber: Bool {
        guard let exp = subscriptionExpiresAt else { return false }
        return exp > .now
    }

    public func canStart(freeDaily: Int) -> Bool {
        if isSubscriber { return true }
        if paidCredits > 0 { return true }
        if freeUsedToday < freeDaily { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case freeUsedToday, day, paidCredits, subscriptionExpiresAt, referralCode, referredBy, referralsConsumed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        freeUsedToday = (try? c.decode(Int.self, forKey: .freeUsedToday)) ?? 0
        day = (try? c.decode(String.self, forKey: .day)) ?? ""
        paidCredits = (try? c.decode(Int.self, forKey: .paidCredits)) ?? 0
        if let ms = try? c.decode(Double.self, forKey: .subscriptionExpiresAt) {
            subscriptionExpiresAt = Date(timeIntervalSince1970: ms / 1000)
        } else {
            subscriptionExpiresAt = nil
        }
        // try? + decode flattens to String?; try? + decodeIfPresent would
        // produce String?? which can't assign to a String? property.
        referralCode = try? c.decode(String.self, forKey: .referralCode)
        referredBy = try? c.decode(String.self, forKey: .referredBy)
        referralsConsumed = (try? c.decode(Int.self, forKey: .referralsConsumed)) ?? 0
    }

    public init(freeUsedToday: Int, day: String, paidCredits: Int,
                subscriptionExpiresAt: Date?, referralCode: String?,
                referredBy: String?, referralsConsumed: Int) {
        self.freeUsedToday = freeUsedToday
        self.day = day
        self.paidCredits = paidCredits
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.referralCode = referralCode
        self.referredBy = referredBy
        self.referralsConsumed = referralsConsumed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(freeUsedToday, forKey: .freeUsedToday)
        try c.encode(day, forKey: .day)
        try c.encode(paidCredits, forKey: .paidCredits)
        if let s = subscriptionExpiresAt {
            try c.encode(s.timeIntervalSince1970 * 1000, forKey: .subscriptionExpiresAt)
        }
        try c.encodeIfPresent(referralCode, forKey: .referralCode)
        try c.encodeIfPresent(referredBy, forKey: .referredBy)
        try c.encode(referralsConsumed, forKey: .referralsConsumed)
    }
}

public struct ReferralOutcome: Sendable, Codable {
    public let ok: Bool
    public let bonusCreditsToYou: Int?
    public let inviterAwarded: Bool?
    public let inviterCapped: Bool?
}

#if canImport(DeviceCheck)
public actor EntitlementClient {
    private let workerBaseURL: URL
    private let attest: AttestService
    private let session: URLSession

    public init(workerBaseURL: URL, attest: AttestService, session: URLSession = .shared) {
        self.workerBaseURL = workerBaseURL
        self.attest = attest
        self.session = session
    }

    public func fetch() async throws -> Entitlement {
        let keyId = try await attest.ensureRegistered()
        var url = workerBaseURL.appendingPathComponent("v1/entitlements")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "keyId", value: keyId)]
        url = comps.url!
        let (data, resp) = try await session.data(from: url)
        try assertOK(resp, data: data)
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    public func redeemIAP(jws: String) async throws {
        let keyId = try await attest.ensureRegistered()
        let payload: [String: String] = ["jws": jws, "keyId": keyId]
        let payloadBytes = try canonicalJSON(payload)
        let signature = try await attest.signAssertion(payload: payloadBytes)
        var dict: [String: Any] = ["keyId": keyId, "jws": jws, "attestation": signature.bodyDict()]
        try await postSigned(path: "v1/iap/redeem", dict: &dict, devHmac: signature.devBypassHmac)
    }

    public func myReferralCode() async throws -> String {
        let keyId = try await attest.ensureRegistered()
        let payload: [String: String] = ["keyId": keyId]
        let payloadBytes = try canonicalJSON(payload)
        let signature = try await attest.signAssertion(payload: payloadBytes)
        var dict: [String: Any] = ["keyId": keyId, "attestation": signature.bodyDict()]
        let data = try await postSigned(path: "v1/referral/code", dict: &dict, devHmac: signature.devBypassHmac)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = obj?["code"] as? String else { throw AttestError.network("missing code") }
        return code
    }

    public func redeemReferral(code: String) async throws -> ReferralOutcome {
        let keyId = try await attest.ensureRegistered()
        let payload: [String: String] = ["code": code, "keyId": keyId]
        let payloadBytes = try canonicalJSON(payload)
        let signature = try await attest.signAssertion(payload: payloadBytes)
        var dict: [String: Any] = ["keyId": keyId, "code": code, "attestation": signature.bodyDict()]
        let data = try await postSigned(path: "v1/referral/redeem", dict: &dict, devHmac: signature.devBypassHmac)
        return try JSONDecoder().decode(ReferralOutcome.self, from: data)
    }

    // MARK: - helpers

    @discardableResult
    private func postSigned(path: String, dict: inout [String: Any], devHmac: String?) async throws -> Data {
        let url = workerBaseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let devHmac { req.setValue(devHmac, forHTTPHeaderField: "X-Dev-Bypass") }
        req.httpBody = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        let (data, resp) = try await session.data(for: req)
        try assertOK(resp, data: data)
        return data
    }

    private func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func assertOK(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw AttestError.network("not http")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "\(http.statusCode)"
            throw AttestError.serverRejected(msg)
        }
    }
}
#endif
