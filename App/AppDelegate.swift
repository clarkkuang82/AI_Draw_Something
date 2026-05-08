import UIKit
import GoogleMobileAds
import AppTrackingTransparency

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        MobileAds.shared.start()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard #available(iOS 14, *) else { return }
        ATTrackingManager.requestTrackingAuthorization { _ in }
    }
}
