import Network
import SwiftUI
import UIKit

// Swift mirror of HighlightsPlayerScreen.kt - full-screen player for a
// game's official highlights video. Landscape-locking isn't ported (SwiftUI
// makes forcing orientation nontrivial and the embed's own fullscreen
// button already covers rotation reasonably); everything else - the
// Wi-Fi-only gate, and falling back to the YouTube app/browser when a video
// has embedding disabled - is.
struct HighlightsPlayerView: View {
    let videoId: String
    let wifiOnlyEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var isOnWifi = Self.checkWifi()
    @State private var proceedOnCellular = false
    @State private var playerReady = false
    @State private var errorMessage: String?

    private var needsWifiPrompt: Bool {
        wifiOnlyEnabled && !isOnWifi && !proceedOnCellular
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if needsWifiPrompt {
                WifiOnlyPrompt(
                    onWatchAnyway: { proceedOnCellular = true },
                    onCancel: { dismiss() }
                )
            } else if let errorMessage {
                CenteredError(message: errorMessage)
            } else {
                YouTubeEmbedWebView(
                    videoId: videoId,
                    onReady: { playerReady = true },
                    onError: handlePlayerError
                )
                .ignoresSafeArea()
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.4), in: Circle())
            }
            .padding(12)
        }
    }

    // YouTube error codes 101/150 both mean "the video owner has disabled
    // embedded playback" (Android's PlayerConstants.VIDEO_NOT_PLAYABLE_IN_
    // EMBEDDED_PLAYER maps to the same underlying restriction) - nothing
    // this screen can do about it, so bounce straight to the YouTube app/
    // browser instead of dead-ending on an error the user can't act on.
    private func handlePlayerError(code: Int) {
        if code == 101 || code == 150, let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
            UIApplication.shared.open(url)
            dismiss()
        } else {
            errorMessage = "Couldn't play this video (error \(code))."
        }
    }

    private static func checkWifi() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        monitor.pathUpdateHandler = { path in
            result = path.usesInterfaceType(.wifi)
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "wifi-check")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 1)
        monitor.cancel()
        return result
    }
}

private struct WifiOnlyPrompt: View {
    let onWatchAnyway: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("You're not on Wi-Fi")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Watching this highlight will use mobile data. Wi-Fi-only playback is on in Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
            Button("Watch on Mobile Data", action: onWatchAnyway)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CenteredError: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HighlightsPlayerView(videoId: "dQw4w9WgXcQ", wifiOnlyEnabled: false)
}
