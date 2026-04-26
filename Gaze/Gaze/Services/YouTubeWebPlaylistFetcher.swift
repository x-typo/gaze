import Foundation
import WebKit

@MainActor
final class YouTubeWebPlaylistFetcher: NSObject {
    static let shared = YouTubeWebPlaylistFetcher()

    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?
    private var didComplete = false
    private var timeoutTask: Task<Void, Never>?

    func playlists() async throws -> PlaylistPage {
        try PlaylistResponseParser.playlistPage(from: try await initialData(from: Self.playlistsURL))
    }

    func playlistVideos(playlistID: String) async throws -> PlaylistVideoPage {
        try VideoResponseParser.playlistVideoPage(
            from: try await initialData(from: Self.playlistURL(playlistID: playlistID))
        )
    }

    private func initialData(from url: URL) async throws -> Data {
        guard continuation == nil else {
            throw YouTubeWebPlaylistFetcherError.alreadyLoading
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                didComplete = false

                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .default()

                let webView = WKWebView(frame: .zero, configuration: configuration)
                webView.navigationDelegate = self
                webView.customUserAgent = YouTubeWebUserAgent.mobileSafari

                self.webView = webView
                scheduleTimeout()

                guard !Task.isCancelled else {
                    cancelLoad(with: CancellationError())
                    return
                }

                webView.load(URLRequest(url: url))
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelLoad(with: CancellationError())
            }
        }
    }

    private func finish(with result: Result<Data, Error>) {
        guard let continuation, !didComplete else {
            return
        }

        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView = nil
        didComplete = true

        switch result {
        case .success(let page):
            continuation.resume(returning: page)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func cancelLoad(with error: Error) {
        webView?.stopLoading()
        finish(with: .failure(error))
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.loadTimeoutNanoseconds)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.cancelLoad(with: YouTubeWebPlaylistFetcherError.timedOut)
            }
        }
    }

    private func extractInitialData(from webView: WKWebView) {
        let script = """
        (() => {
          if (!window.ytInitialData) {
            return null;
          }
          return JSON.stringify(window.ytInitialData);
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else {
                return
            }

            Task { @MainActor in
                if let error {
                    self.finish(with: .failure(error))
                    return
                }

                guard let json = result as? String,
                      let data = json.data(using: .utf8) else {
                    self.finish(with: .failure(YouTubeWebPlaylistFetcherError.missingInitialData))
                    return
                }

                self.finish(with: .success(data))
            }
        }
    }

    private static let playlistsURL = URL(
        string: "https://www.youtube.com/feed/playlists"
    )!

    private static func playlistURL(playlistID: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/playlist"
        components.queryItems = [
            URLQueryItem(name: "list", value: playlistID),
        ]

        return components.url ?? URL(string: "https://www.youtube.com/playlist?list=\(playlistID)")!
    }

    private static let loadTimeoutNanoseconds: UInt64 = 20 * 1_000_000_000
}

extension YouTubeWebPlaylistFetcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extractInitialData(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: .failure(error))
    }
}

private nonisolated enum YouTubeWebPlaylistFetcherError: LocalizedError {
    case alreadyLoading
    case missingInitialData
    case timedOut

    var errorDescription: String? {
        switch self {
        case .alreadyLoading:
            "A YouTube playlists page load is already in progress."
        case .missingInitialData:
            "YouTube playlists page did not expose initial data."
        case .timedOut:
            "Timed out loading YouTube playlists."
        }
    }
}
