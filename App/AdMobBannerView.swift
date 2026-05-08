import SwiftUI
import UIKit
import GoogleMobileAds

/// Bottom-anchored adaptive banner. Uses Google's sample ad unit so it always
/// fills — swap to a real production unit ID once the AdMob app is registered.
struct AdMobBannerView: View {
    var body: some View {
        let width = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        BannerViewContainer(adSize)
            .frame(width: adSize.size.width, height: adSize.size.height)
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    typealias UIViewType = BannerView
    let adSize: AdSize

    init(_ adSize: AdSize) { self.adSize = adSize }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        // Google's always-fill sample banner unit. Replace with the real unit ID
        // once an AdMob app is registered for AI Draw Something.
        banner.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            #if DEBUG
            print("AdMob banner loaded.")
            #endif
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            print("AdMob banner failed to load: \(error.localizedDescription)")
            #endif
        }
    }
}
