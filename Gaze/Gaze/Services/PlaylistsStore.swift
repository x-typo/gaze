import Foundation
import Observation

@Observable
@MainActor
final class PlaylistsStore {
    var playlists: [Playlist] = []
    var continuation: String?
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var paginationErrorMessage: String?
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

    func load(authContext: YouTubeAuthContext, force: Bool = false) async {
        guard !isLoading,
              !isLoadingMore else {
            return
        }

        guard force || !hasLoaded else {
            return
        }

        isLoading = true
        errorMessage = nil
        paginationErrorMessage = nil
        defer {
            isLoading = false
        }

        do {
            let page = try await webFetcher.playlists()
            guard !Task.isCancelled else {
                return
            }

            playlists = page.playlists
            continuation = page.continuation
            errorMessage = nil
            paginationErrorMessage = nil
            hasLoaded = true
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            await loadWithNativeInnertubeFallback(authContext: authContext, webError: error)
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
        paginationErrorMessage = nil
        defer {
            isLoadingMore = false
        }

        do {
            let page = try await client.playlists(
                authContext: authContext,
                continuation: currentContinuation
            )
            guard !Task.isCancelled,
                  self.continuation == currentContinuation else {
                return
            }

            appendUnique(page.playlists)
            self.continuation = page.continuation
            paginationErrorMessage = nil
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            paginationErrorMessage = error.localizedDescription
        }
    }

    private func loadWithNativeInnertubeFallback(
        authContext: YouTubeAuthContext,
        webError: Error
    ) async {
        do {
            let page = try await client.playlists(authContext: authContext)
            guard !Task.isCancelled else {
                return
            }

            playlists = page.playlists
            continuation = page.continuation
            errorMessage = nil
            paginationErrorMessage = nil
            hasLoaded = true
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            playlists = []
            continuation = nil
            paginationErrorMessage = nil
            errorMessage = [
                "Web playlist extraction failed: \(webError.localizedDescription)",
                "Native playlist request failed: \(error.localizedDescription)",
            ].joined(separator: " ")
            hasLoaded = true
        }
    }

    func fail(with error: Error) {
        playlists = []
        continuation = nil
        errorMessage = error.localizedDescription
        paginationErrorMessage = nil
        hasLoaded = true
        isLoading = false
        isLoadingMore = false
    }

    func failLoadingMore(with error: Error) {
        paginationErrorMessage = error.localizedDescription
        isLoadingMore = false
    }

    func reset() {
        playlists = []
        continuation = nil
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        paginationErrorMessage = nil
        hasLoaded = false
    }

    private func appendUnique(_ playlists: [Playlist]) {
        var seenPlaylistIDs = Set(self.playlists.map(\.id))
        let newPlaylists = playlists.filter { seenPlaylistIDs.insert($0.id).inserted }
        self.playlists.append(contentsOf: newPlaylists)
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
