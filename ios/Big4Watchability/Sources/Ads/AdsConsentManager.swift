import Foundation
import UserMessagingPlatform
import GoogleMobileAds

// Swift mirror of mobile/app/.../ads/ConsentManager.kt - wraps Google's User
// Messaging Platform SDK so the GDPR/UK consent flow resolves BEFORE
// MobileAds.start() and before any ad request. That ordering is an AdMob
// policy requirement, not a nicety: requesting an ad first is a policy
// violation even if the consent form is shown a moment later.
//
// iOS adds one thing Android has no equivalent for - App Tracking
// Transparency. UMP presents the ATT prompt for us as part of the same form
// flow when the configuration calls for it, which is why this is the only
// place that has to care about ATT at all.
//
// Fails OPEN, matching Android: if the consent SDK itself errors, ads are
// still requested. Google's own guidance is that a UMP failure shouldn't
// black out a publisher's inventory, and in non-GDPR regions (which is most
// of this app's audience) there's nothing to consent to anyway.

@MainActor
final class AdsConsentManager: ObservableObject {
    static let shared = AdsConsentManager()

    /// False until consent is resolved one way or the other. AdBannerView
    /// reserves its height but renders no ad while this is false.
    @Published private(set) var canRequestAds = false

    private var hasStarted = false

    /// True only when the bundle actually carries an AdMob app id. Without
    /// it the Google Mobile Ads SDK raises GADInvalidInitializationException,
    /// an Objective-C exception Swift cannot catch - i.e. a hard crash at
    /// launch, which is what build 12 did on a real device. Checking first
    /// makes ads degrade to a no-op instead, the same stance
    /// PushNotificationManager takes on a missing GoogleService-Info.plist
    /// and the backend takes on an unset FIREBASE_SERVICE_ACCOUNT.
    ///
    /// project.yml force-writes this key via PlistBuddy so it should always
    /// be present - this guard exists because "should" is what shipped a
    /// crashing build, and an app that silently drops ads is infinitely
    /// preferable to one that won't open.
    private var hasAdMobAppId: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        return !(id ?? "").isEmpty
    }

    /// Called once from the AppDelegate's didFinishLaunching - early enough
    /// that consent is usually resolved before the user reaches a screen
    /// with a banner on it.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard hasAdMobAppId else {
            print("[ads] GADApplicationIdentifier missing from Info.plist - ads disabled, app continues")
            return
        }

        let parameters = RequestParameters()
        // No under-13 content and no child-directed treatment declared -
        // matches the Play Store data-safety answers already filed for
        // Android (target audience is general, 3+ rating).
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            guard let self else { return }
            if let error {
                print("[ads] consent info update failed, failing open: \(error.localizedDescription)")
                self.finish()
                return
            }
            ConsentForm.loadAndPresentIfRequired(from: nil) { formError in
                if let formError {
                    print("[ads] consent form failed, failing open: \(formError.localizedDescription)")
                }
                self.finish()
            }
        }
    }

    /// Backs the "Ad privacy options" row in AboutView - only worth showing
    /// when the user is actually in a region with a privacy-options form.
    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() {
        ConsentForm.presentPrivacyOptionsForm(from: nil) { error in
            if let error {
                print("[ads] privacy options form failed: \(error.localizedDescription)")
            }
        }
    }

    private func finish() {
        canRequestAds = ConsentInformation.shared.canRequestAds
        if canRequestAds {
            // Idempotent, and deliberately not called any earlier than this.
            MobileAds.shared.start(completionHandler: nil)
        }
    }
}
