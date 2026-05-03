import XCTest
@testable import Networking

/// The Worker EntitlementDO sends entitlement state as JSON with
/// subscriptionExpiresAt encoded as ms-since-epoch. The iOS side decodes
/// that into Date. canStart() then drives the paywall gate. These tests
/// pin the decoder + the gate logic.
final class EntitlementTests: XCTestCase {
    private func decode(_ json: String) throws -> Entitlement {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    func test_decode_full_object_with_subscription() throws {
        let ms = Date.now.addingTimeInterval(86_400).timeIntervalSince1970 * 1000
        let json = """
        {"freeUsedToday":2,"day":"2026-05-03","paidCredits":10,
         "subscriptionExpiresAt":\(ms),
         "referralCode":"K7M2QX","referralsConsumed":3}
        """
        let e = try decode(json)
        XCTAssertEqual(e.freeUsedToday, 2)
        XCTAssertEqual(e.paidCredits, 10)
        XCTAssertEqual(e.referralCode, "K7M2QX")
        XCTAssertEqual(e.referralsConsumed, 3)
        XCTAssertNotNil(e.subscriptionExpiresAt)
        XCTAssertTrue(e.isSubscriber)
    }

    func test_decode_without_subscription_keeps_nil() throws {
        let json = #"{"freeUsedToday":0,"day":"2026-05-03","paidCredits":0,"referralsConsumed":0}"#
        let e = try decode(json)
        XCTAssertNil(e.subscriptionExpiresAt)
        XCTAssertFalse(e.isSubscriber)
    }

    func test_decode_with_expired_subscription_reports_not_subscriber() throws {
        let ms = Date.now.addingTimeInterval(-86_400).timeIntervalSince1970 * 1000
        let json = """
        {"freeUsedToday":0,"day":"2026-05-03","paidCredits":0,
         "subscriptionExpiresAt":\(ms),"referralsConsumed":0}
        """
        let e = try decode(json)
        XCTAssertFalse(e.isSubscriber)
    }

    func test_canStart_passes_when_under_free_quota() {
        let e = Entitlement(freeUsedToday: 2, day: "x",
                            paidCredits: 0, subscriptionExpiresAt: nil,
                            referralCode: nil, referredBy: nil,
                            referralsConsumed: 0)
        XCTAssertTrue(e.canStart(freeDaily: 3))
    }

    func test_canStart_fails_when_quota_used_and_no_credits() {
        let e = Entitlement(freeUsedToday: 3, day: "x",
                            paidCredits: 0, subscriptionExpiresAt: nil,
                            referralCode: nil, referredBy: nil,
                            referralsConsumed: 0)
        XCTAssertFalse(e.canStart(freeDaily: 3))
    }

    func test_canStart_passes_with_paid_credits() {
        let e = Entitlement(freeUsedToday: 99, day: "x",
                            paidCredits: 1, subscriptionExpiresAt: nil,
                            referralCode: nil, referredBy: nil,
                            referralsConsumed: 0)
        XCTAssertTrue(e.canStart(freeDaily: 3))
    }

    func test_canStart_passes_for_active_subscriber() {
        let e = Entitlement(freeUsedToday: 99, day: "x",
                            paidCredits: 0,
                            subscriptionExpiresAt: Date.now.addingTimeInterval(3600),
                            referralCode: nil, referredBy: nil,
                            referralsConsumed: 0)
        XCTAssertTrue(e.canStart(freeDaily: 3))
    }
}
