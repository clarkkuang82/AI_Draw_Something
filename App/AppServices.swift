import Foundation
import GameCore
import Networking
import Persistence
import Attest
#if canImport(StoreKit)
import Commerce
#endif

/// One place to wire dependencies. Switch behavior based on whether the
/// app was built with a Worker URL (Info.plist key `WorkerBaseURL`).
///   - WorkerBaseURL set     → AttestedGuessClient + IAP + Referral + Paywall
///   - WorkerBaseURL unset   → DirectGuessClient (BYOK), no paywall, MVP path
public struct AppServices {
    public let gameStore: GameStore
    public let entitlementStore: EntitlementStore?
    public let iapStore: IAPStore?
    public let referralFlow: ReferralFlow?
    public let isAttestedMode: Bool

    @MainActor
    public init(catalog: any WordCatalog) {
        if let worker = Self.workerBaseURL {
            let attestConfig = AttestConfig(
                workerBaseURL: worker,
                devBypassSecret: Self.devBypassSecret
            )
            let attest = AttestService(config: attestConfig)
            let entitlementClient = EntitlementClient(workerBaseURL: worker, attest: attest)
            let guesser = AttestedGuessClient(workerBaseURL: worker, attest: attest)
            self.gameStore = GameStore(catalog: catalog, guesser: guesser)
            #if canImport(StoreKit)
            self.entitlementStore = EntitlementStore(client: entitlementClient)
            self.iapStore = IAPStore(entitlementClient: entitlementClient)
            self.referralFlow = ReferralFlow(client: entitlementClient)
            #else
            self.entitlementStore = nil
            self.iapStore = nil
            self.referralFlow = nil
            #endif
            self.isAttestedMode = true
        } else {
            let guesser = DirectGuessClient(keyResolver: { provider in
                switch provider {
                case .anthropic: return APIKeyStore.anthropicKey()
                case .openai:    return APIKeyStore.openAIKey()
                }
            })
            self.gameStore = GameStore(catalog: catalog, guesser: guesser)
            self.entitlementStore = nil
            self.iapStore = nil
            self.referralFlow = nil
            self.isAttestedMode = false
        }
        if let raw = UserDefaults.standard.string(forKey: SettingsKey.providerHint),
           let hint = ProviderHint(rawValue: raw) {
            gameStore.providerHint = hint
        }
    }

    private static var workerBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WorkerBaseURL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    private static var devBypassSecret: String? {
        #if DEBUG
        return Bundle.main.object(forInfoDictionaryKey: "DevBypassSecret") as? String
        #else
        return nil
        #endif
    }
}
