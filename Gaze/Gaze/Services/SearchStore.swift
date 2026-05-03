import Foundation
import Observation

@Observable
@MainActor
final class SearchStore {
    var query = ""
    var results: [Video] = []
    var continuation: String?
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var paginationErrorMessage: String?
    var hasSearched = false

    @ObservationIgnored private var activeSearchID = UUID()
    private let client: YouTubeClient

    init(client: YouTubeClient = .shared) {
        self.client = client
    }

    func searchVideos(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            reset()
            return
        }

        let searchID = UUID()
        activeSearchID = searchID
        self.query = trimmedQuery
        hasSearched = true
        isLoading = true
        errorMessage = nil
        paginationErrorMessage = nil
        defer {
            if activeSearchID == searchID {
                isLoading = false
            }
        }

        do {
            let page = try await client.searchVideos(query: trimmedQuery)
            guard !Task.isCancelled,
                  activeSearchID == searchID else {
                return
            }

            results = page.videos
            continuation = page.continuation
            errorMessage = nil
            paginationErrorMessage = nil
        } catch {
            guard activeSearchID == searchID,
                  !Self.isCancellation(error) else {
                return
            }

            results = []
            continuation = nil
            errorMessage = error.localizedDescription
            paginationErrorMessage = nil
        }
    }

    func loadMore() async {
        guard !isLoading,
              !isLoadingMore,
              let continuation,
              !query.isEmpty else {
            return
        }

        let searchID = activeSearchID
        let currentQuery = query
        let currentContinuation = continuation

        isLoadingMore = true
        paginationErrorMessage = nil
        defer {
            isLoadingMore = false
        }

        do {
            let page = try await client.searchVideos(
                query: currentQuery,
                continuation: currentContinuation
            )
            guard !Task.isCancelled,
                  activeSearchID == searchID,
                  query == currentQuery else {
                return
            }

            appendUnique(page.videos)
            self.continuation = page.continuation
            paginationErrorMessage = nil
        } catch {
            guard activeSearchID == searchID,
                  query == currentQuery,
                  !Self.isCancellation(error) else {
                return
            }

            paginationErrorMessage = error.localizedDescription
        }
    }

    func reset() {
        activeSearchID = UUID()
        query = ""
        results = []
        continuation = nil
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        paginationErrorMessage = nil
        hasSearched = false
    }

    private func appendUnique(_ videos: [Video]) {
        var seenVideoIDs = Set(results.map(\.id))
        let newVideos = videos.filter { seenVideoIDs.insert($0.id).inserted }
        results.append(contentsOf: newVideos)
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
