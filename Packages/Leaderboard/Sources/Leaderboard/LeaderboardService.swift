#if canImport(GameKit) && canImport(UIKit)
import Foundation
import GameKit
import UIKit
import Observation

/// Lifetime-score leaderboard. We submit only on .gameOver to keep within
/// GameCenter quota and avoid Sandbox flakiness during a round.
@MainActor
@Observable
public final class LeaderboardService {
    public static let leaderboardId = "aidraw.score.v1"

    public private(set) var isAuthenticated = false
    public private(set) var lastError: String?

    public init() {}

    public func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, error in
            guard let self else { return }
            if let vc {
                Self.present(vc)
            } else if GKLocalPlayer.local.isAuthenticated {
                self.isAuthenticated = true
            } else if let error {
                self.lastError = error.localizedDescription
            }
        }
    }

    public func submit(score: Int) async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.leaderboardId]
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController
        else { return }
        var presenter: UIViewController = root
        while let next = presenter.presentedViewController { presenter = next }
        presenter.present(vc, animated: true)
    }
}
#endif
