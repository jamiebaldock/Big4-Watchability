import SwiftUI

@main
struct Big4WatchabilityApp: App {
    // SwiftUI has no hook for the APNs registration callbacks, and the ads
    // consent flow wants to start as early as possible, so both are driven
    // from a real UIApplicationDelegate (see PushNotificationManager.swift).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
