#if canImport(StoreKit) && canImport(SwiftUI)
import SwiftUI
import StoreKit

public struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var store: IAPStore
    public var entitlement: EntitlementStore
    public var referral: ReferralFlow
    public var onDone: () -> Void

    @State private var redeemCode: String = ""
    @State private var purchaseError: String?

    public init(store: IAPStore,
                entitlement: EntitlementStore,
                referral: ReferralFlow,
                onDone: @escaping () -> Void) {
        self.store = store
        self.entitlement = entitlement
        self.referral = referral
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    productList
                    referralSection
                    Text("通过 Apple ID 自动续订。在“设置 → 订阅”可以随时取消。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                    Button("恢复购买") {
                        Task { await store.restorePurchases(); await entitlement.refresh() }
                    }
                    .font(.footnote)
                    if let purchaseError {
                        Text(purchaseError).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("继续游戏")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { onDone(); dismiss() }
                }
            }
            .task { await store.loadProducts() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("今天的免费局数已用完")
                .font(.title2.bold())
            Text(entitlement.hudText)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var productList: some View {
        if store.isLoading {
            ProgressView()
        } else if store.products.isEmpty {
            Text("暂无可用商品").foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    ProductRow(product: product) {
                        await purchase(product)
                    }
                }
            }
        }
    }

    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 4)
            Text("或者用邀请码").font(.headline)
            HStack {
                TextField("好友的邀请码", text: $redeemCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("兑换") {
                    Task {
                        await referral.redeem(code: redeemCode)
                        await entitlement.refresh()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(redeemCode.count < 4 || referral.isWorking)
            }
            if let outcome = referral.lastOutcome, outcome.ok {
                Text("已发送 \(outcome.bonusCreditsToYou ?? 0) 局奖励")
                    .font(.footnote).foregroundStyle(.green)
            }
            if let err = referral.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func purchase(_ product: Product) async {
        do {
            try await store.purchase(product)
            await entitlement.refresh()
            onDone()
            dismiss()
        } catch IAPError.userCancelled {
            // ignore
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}

private struct ProductRow: View {
    let product: Product
    let onTap: () async -> Void

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.headline)
                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice).font(.headline.monospacedDigit())
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.95)))
        }
        .buttonStyle(.plain)
    }
}
#endif
