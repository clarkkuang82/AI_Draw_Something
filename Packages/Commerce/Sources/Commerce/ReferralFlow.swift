#if canImport(DeviceCheck)
import Foundation
import Networking
import Observation

@MainActor
@Observable
public final class ReferralFlow {
    public private(set) var myCode: String?
    public private(set) var lastOutcome: ReferralOutcome?
    public private(set) var lastError: String?
    public private(set) var isWorking = false

    private let client: EntitlementClient

    public init(client: EntitlementClient) {
        self.client = client
    }

    public func loadMyCode() async {
        isWorking = true; defer { isWorking = false }
        do {
            myCode = try await client.myReferralCode()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func redeem(code: String) async {
        isWorking = true; defer { isWorking = false }
        do {
            lastOutcome = try await client.redeemReferral(code: code)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
#endif
