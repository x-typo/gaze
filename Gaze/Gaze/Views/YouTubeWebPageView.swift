import SwiftUI
import WebKit

struct YouTubeWebPageView: View {
    static let playlistsURL = URL(string: "https://www.youtube.com/feed/playlists")!

    @Environment(\.dismiss) private var dismiss
    @Environment(YouTubeSession.self) private var youtubeSession

    let title: String
    let url: URL

    var body: some View {
        YouTubeWebPageRepresentable(url: url) { url, cookies in
            _ = youtubeSession.handleLoginNavigation(url: url, cookies: cookies)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct YouTubeWebPageRepresentable: UIViewRepresentable {
    let url: URL
    let onNavigationFinished: (URL?, [HTTPCookie]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = Self.mobileSafariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationFinished: onNavigationFinished)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationFinished: (URL?, [HTTPCookie]) -> Void

        init(onNavigationFinished: @escaping (URL?, [HTTPCookie]) -> Void) {
            self.onNavigationFinished = onNavigationFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self, weak webView] cookies in
                guard let self else {
                    return
                }

                Task { @MainActor in
                    self.onNavigationFinished(webView?.url, cookies)
                }
            }
        }
    }

    private static let mobileSafariUserAgent = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/18.0 Mobile/15E148 Safari/604.1",
    ].joined(separator: " ")
}
