import SwiftUI
import GoogleMobileAds

// Swift mirror of mobile/app/.../ui/AdBanner.kt - the anchored banner pinned
// above the tab bar, same placement, same reserved height, same
// consent-before-load ordering.
//
// AD UNIT IDs ARE PER-PLATFORM. Android's real unit
// (ca-app-pub-6295039345620062/5400756591) cannot be reused here - iOS needs
// its own app registered in the same AdMob account and its own banner unit.
// Until James creates those, this deliberately ships Google's official iOS
// TEST ids: they serve real sample ads, are safe in production, and earn
// nothing. Swapping them is a two-line change here plus the matching
// GADApplicationIdentifier in ios/project.yml. This is exactly how Android
// shipped too - test ids first (v3), real ids later (v4, 2026-09-16).
private enum AdUnit {
    static let testBanner = "ca-app-pub-3940256099942544/2934735716"

    /// Swap to the real iOS banner unit id once it exists in AdMob.
    static var banner: String { testBanner }
}

/// 320x50 is the standard banner - reserve its height unconditionally so the
/// row keeps a stable size whether or not an ad has filled yet. Android hit a
/// real bug here (the banner collapsed to zero height until first fill and
/// shifted the layout when it loaded); reserving up front avoids repeating it.
private let bannerHeight: CGFloat = 50

/// Anchored banner, rendered by RootView directly above the TabView's bar
/// rather than inline in scrolling content - a fixed placement every tab
/// shares, so it never shifts as a list scrolls underneath.
///
/// Renders nothing but reserved space until AdsConsentManager resolves
/// whether ads may be requested at all.
struct AdBannerView: View {
    @ObservedObject private var consent = AdsConsentManager.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.surfaceCardElevated
            if consent.canRequestAds {
                BannerViewRepresentable()
            }
        }
        .frame(height: bannerHeight)
        .frame(maxWidth: .infinity)
    }
}

private struct BannerViewRepresentable: UIViewRepresentable {

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdUnit.banner
        banner.delegate = context.coordinator
        // The SDK needs a view controller to present the ad's own full-screen
        // takeover from when tapped. Walking to the key window's root is the
        // standard approach in a SwiftUI app with no UIKit hierarchy to hand.
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("[ads] banner loaded")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // Expected for a brand-new ad unit with no request history -
            // Android saw the same thing on 2026-09-16 and it resolved on its
            // own within hours. Logged, never surfaced to the user.
            print("[ads] banner failed to load: \(error.localizedDescription)")
        }
    }
}
