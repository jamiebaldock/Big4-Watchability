import Foundation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// The iOS half of the Alerts feature's push plumbing - the rough equivalent
// of Android's AlertsFirebaseMessagingService, plus the APNs registration
// Android doesn't need.
//
// WHY FIREBASE AND NOT RAW APNs: the backend already speaks FCM and stores
// one `fcm_token` per device. Firebase's iOS SDK registers with APNs, then
// exchanges the APNs token for an FCM token - so iOS devices slot into the
// exact same column, the same send path and the same dead-token pruning
// with no second sender and no platform branch. The only server-side change
// the iOS port needed at all was an `apns` payload block (fcm.ts), because
// APNs drops a push that has no `aps` dictionary - the data-only message
// Android relies on is silently never delivered to an iPhone.
//
// DEGRADES TO INERT, deliberately, exactly like the backend does when
// FIREBASE_SERVICE_ACCOUNT is unset: with no GoogleService-Info.plist in the
// bundle, Firebase is never configured, no token is ever requested, and the
// app runs completely normally with alerts simply off. FirebaseApp.configure()
// hard-crashes on a missing plist, so the check below is load-bearing, not
// defensive dressing - it's what lets CI build and TestFlight run before
// James has finished the Firebase console setup.

/// Set by a notification tap, observed by RootView to deep-link to the game.
/// Mirrors the intent extras Android's AlertsFirebaseMessagingService reads.
struct AlertDeepLink: Equatable {
    let eventId: String
    let leagueGroup: LeagueGroup?
    let tipoffUtc: String?
}

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    /// Non-nil for one render pass after a notification tap; RootView
    /// consumes it and sets it back to nil.
    @Published var pendingDeepLink: AlertDeepLink?
    /// The in-app banner for the "in_app"/"both" delivery prefs - shown when
    /// a push lands while the app is foregrounded.
    @Published var inAppBanner: (title: String, body: String)?
    @Published private(set) var authorizationDenied = false

    private var isFirebaseConfigured = false

    /// True once the bundle actually contains Firebase config. Everything
    /// push-related is a no-op when this is false.
    private var hasFirebaseConfig: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    /// Called from the AppDelegate's didFinishLaunching. Safe to call when
    /// Firebase config is absent - it just does nothing.
    func configureIfPossible() {
        guard hasFirebaseConfig else {
            print("[push] GoogleService-Info.plist not in bundle - alerts are inert until it is")
            return
        }
        guard !isFirebaseConfigured else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        isFirebaseConfigured = true
    }

    /// Asks for notification permission and, if granted, registers with
    /// APNs. Called when the user turns an alert type on in
    /// AlertsSettingsView - never at cold start, so a first-run user isn't
    /// hit with a permission prompt before they know what the app is.
    func requestAuthorizationIfNeeded() async {
        guard isFirebaseConfigured else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorizationDenied = !granted
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .denied:
            authorizationDenied = true
        default:
            authorizationDenied = false
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Handed the raw APNs token by the AppDelegate - Firebase needs it
    /// explicitly before it will mint an FCM token.
    func setAPNsToken(_ deviceToken: Data) {
        guard isFirebaseConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }
}

// MARK: - FCM token rotation

extension PushNotificationManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            AlertsStore.shared.setFcmToken(fcmToken)
            // A rotated token is useless to the server until it's re-sent,
            // so push the full device state straight back up. Same reason
            // Android re-registers from onNewToken.
            await AlertsViewModel.syncRegistration()
        }
    }
}

// MARK: - Foreground presentation + taps

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    /// A push arrived while the app is open. The delivery pref decides what
    /// that should look like - "push only" lets iOS draw its usual banner,
    /// anything including in-app draws ours instead, so the user doesn't
    /// get the same alert twice at once.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let fallbackTitle = notification.request.content.title
        let fallbackBody = notification.request.content.body
        // Explicit closure signature: a multi-statement closure returning an
        // OptionSet trips up Swift's inference, and `[]` alone is ambiguous.
        return await MainActor.run { () -> UNNotificationPresentationOptions in
            switch AlertsStore.shared.settings.delivery {
            case .push:
                return [.banner, .sound]
            case .inApp, .both:
                self.inAppBanner = (
                    title: info["title"] as? String ?? fallbackTitle,
                    body: info["body"] as? String ?? fallbackBody
                )
                return []
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let eventId = info["eventId"] as? String else { return }
        await MainActor.run {
            self.pendingDeepLink = AlertDeepLink(
                eventId: eventId,
                leagueGroup: (info["lg"] as? String).flatMap(LeagueGroup.init(rawValue:)),
                tipoffUtc: info["utc"] as? String
            )
        }
    }
}

// MARK: - AppDelegate

/// SwiftUI has no hook for the APNs registration callbacks, so the app needs
/// a real UIApplicationDelegate purely to forward them. Attached via
/// @UIApplicationDelegateAdaptor in Big4WatchabilityApp.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            PushNotificationManager.shared.configureIfPossible()
            AdsConsentManager.shared.start()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        MainActor.assumeIsolated {
            PushNotificationManager.shared.setAPNsToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected and harmless in the Simulator (no APNs there at all) -
        // logged rather than surfaced so it doesn't read as a real fault.
        print("[push] APNs registration failed: \(error.localizedDescription)")
    }
}
