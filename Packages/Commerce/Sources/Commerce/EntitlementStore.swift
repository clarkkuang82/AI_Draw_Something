#if canImport(DeviceCheck)
import Foundation
import Networking
import Observation

@MainActor
@Observable
public final class EntitlementStore {
    public private(set) var entitlement: Entitlement?
    public private(set) var freeDaily: Int
    public private(set) var lastError: String?
    public private(set) var isLoading = false

    private let client: EntitlementClient

    public init(client: EntitlementClient, freeDaily: Int = 3) {
        self.client = client
        self.freeDaily = freeDaily
    }

    public var canStart: Bool {
        guard let entitlement else { return true }   // optimistic before refresh
        return entitlement.canStart(freeDaily: freeDaily)
    }

    public var hudText: String {
        guard let e = entitlement else { return "…" }
        if e.isSubscriber { return "Pro · 不限量" }
        if e.paidCredits > 0 { return "剩余 \(e.paidCredits) 局" }
        return "今日 \(max(0, freeDaily - e.freeUsedToday)) / \(freeDaily)"
    }

    public func refresh() async {
        isLoading = true; defer { isLoading = false }
        do {
            entitlement = try await client.fetch()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
#endif
