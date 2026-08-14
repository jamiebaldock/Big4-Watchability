import SwiftUI
@preconcurrency import WebKit

// Wraps the YouTube IFrame Player API directly (rather than a third-party
// library, since WKWebView doesn't need Android's WebView-reflection/
// 0x0-container workarounds - see HighlightsPlayerScreen.kt for what that
// looked like on the Android side). A local HTML page loads the API script
// and bridges its onReady/onError events back to Swift via a
// WKScriptMessageHandler, matching the structured error signal Android's
// library gets from the same underlying postMessage handshake.
struct YouTubeEmbedWebView: UIViewRepresentable {
    let videoId: String
    let onReady: () -> Void
    let onError: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "playerEvent")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.loadHTMLString(Self.html(videoId: videoId), baseURL: URL(string: "https://www.youtube.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerEvent")
    }

    private static func html(videoId: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            html, body { margin: 0; padding: 0; background: #000; height: 100%; }
            #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(videoId)',
                playerVars: { playsinline: 1, controls: 1, rel: 0 },
                events: {
                  onReady: function() {
                    window.webkit.messageHandlers.playerEvent.postMessage({ type: 'ready' });
                  },
                  onError: function(e) {
                    window.webkit.messageHandlers.playerEvent.postMessage({ type: 'error', code: e.data });
                  }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onReady: () -> Void
        let onError: (Int) -> Void

        init(onReady: @escaping () -> Void, onError: @escaping (Int) -> Void) {
            self.onReady = onReady
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                onReady()
            case "error":
                onError(body["code"] as? Int ?? -1)
            default:
                break
            }
        }
    }
}
