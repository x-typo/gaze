import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(YouTubeSession.self) private var youtubeSession

    var body: some View {
        YouTubeLoginWebView { url, cookies in
            if youtubeSession.handleLoginNavigation(url: url, cookies: cookies) {
                dismiss()
            }
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

private struct YouTubeLoginWebView: UIViewRepresentable {
    let onNavigationFinished: (URL?, [HTTPCookie]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = YouTubeWebUserAgent.mobileSafari
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: Self.loginURL))
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

    private static let loginURL = URL(
        string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F"
    )!

}
