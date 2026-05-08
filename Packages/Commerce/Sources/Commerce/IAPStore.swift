#if canImport(StoreKit) && canImport(DeviceCheck)
import Foundation
import StoreKit
import Networking
import Attest
import Observation

public enum IAPError: Error, LocalizedError {
    case productUnavailable(String)
    case userCancelled
    case pending
    case verificationFailed
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .productUnavailable(let id): return "Product unavailable: \(id)"
        case .userCancelled:              return "User cancelled"
        case .pending:                    return "Purchase pending"
        case .verificationFailed:         return "Apple verification failed"
        case .network(let e):             return e.localizedDescription
        }
    }
}

@MainActor
@Observable
public final class IAPStore {
    public private(set) var products: [Product] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    private let entitlementClient: EntitlementClient
    private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    public init(entitlementClient: EntitlementClient) {
        self.entitlementClient = entitlementClient
        self.transactionListener = Task { [weak self] in
            await self?.observeTransactions()
        }
    }

    deinit { transactionListener?.cancel() }

    public func loadProducts() async {
        isLoading = true; defer { isLoading = false }
        do {
            let products = try await Product.products(for: CommerceConfig.productIdentifiers)
            self.products = products.sorted { $0.price < $1.price }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            try await commit(verification)
        case .userCancelled:
            throw IAPError.userCancelled
        case .pending:
            throw IAPError.pending
        @unknown default:
            throw IAPError.verificationFailed
        }
    }

    public func restorePurchases() async {
        for await verification in Transaction.currentEntitlements {
            try? await commit(verification)
        }
    }

    private func commit(_ verification: VerificationResult<Transaction>) async throws {
        let tx: Transaction
        switch verification {
        case .verified(let v): tx = v
        case .unverified:      throw IAPError.verificationFailed
        }
        do {
            try await entitlementClient.redeemIAP(jws: verification.jwsRepresentation)
        } catch {
            throw IAPError.network(error)
        }
        await tx.finish()
    }

    private func observeTransactions() async {
        for await verification in Transaction.updates {
            try? await commit(verification)
        }
    }
}
#endif
