import Foundation

/// Mirror of the Worker's product catalog. Must match App Store Connect
/// configuration AND `Worker/src/iap/products.ts`.
public enum AIDrawProduct: String, CaseIterable, Sendable {
    case coins20 = "com.aidraw.coins.20"
    case coins100 = "com.aidraw.coins.100"
    case coins500 = "com.aidraw.coins.500"
    case proMonthly = "com.aidraw.pro.month"

    public var isSubscription: Bool { self == .proMonthly }
    public var creditsGranted: Int {
        switch self {
        case .coins20: return 20
        case .coins100: return 100
        case .coins500: return 500
        case .proMonthly: return 0
        }
    }
}

public enum CommerceConfig {
    public static var productIdentifiers: [String] {
        AIDrawProduct.allCases.map(\.rawValue)
    }
}
