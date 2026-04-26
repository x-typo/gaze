import Foundation
import Observation

@Observable
@MainActor
final class PlaylistDetailStore {
    var videos: [Video] = []
    var continuation: String?
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var hasLoaded = false

    private let client: YouTubeClient
    private let webFetcher: YouTubeWebPlaylistFetcher

    init(
        client: YouTubeClient = .shared,
        webFetcher: YouTubeWebPlaylistFetcher? = nil
    ) {
        self.client = client
        self.webFetcher = webFetcher ?? .shared
    }

    func load(playlistID: String, force: Bool = false) async {
        guard !isLoading,
              !isLoadingMore else {
            return
        }

        guard force || !hasLoaded else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            let page = try await webFetcher.playlistVideos(playlistID: playlistID)
            guard !Task.isCancelled else {
                return
            }

            videos = page.videos
            continuation = page.continuation
            hasLoaded = true
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            videos = []
            continuation = nil
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    func loadMore(authContext: YouTubeAuthContext) async {
        guard !isLoading,
              !isLoadingMore,
              let continuation else {
            return
        }

        let currentContinuation = continuation
        isLoadingMore = true
        errorMessage = nil
        defer {
            isLoadingMore = false
        }

        do {
            let page = try await client.playlistVideos(
                authContext: authContext,
                continuation: currentContinuation
            )
            guard !Task.isCancelled,
                  self.continuation == currentContinuation else {
                return
            }

            appendUnique(page.videos)
            self.continuation = page.continuation
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    func failLoadingMore(with error: Error) {
        errorMessage = error.localizedDescription
        isLoadingMore = false
    }

    func reset() {
        videos = []
        continuation = nil
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        hasLoaded = false
    }

    private func appendUnique(_ videos: [Video]) {
        var seenVideoIDs = Set(self.videos.map(\.id))
        let newVideos = videos.filter { seenVideoIDs.insert($0.id).inserted }
        self.videos.append(contentsOf: newVideos)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
