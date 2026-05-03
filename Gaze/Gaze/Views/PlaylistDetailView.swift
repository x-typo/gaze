import SwiftUI

struct PlaylistDetailView: View {
    @Environment(YouTubeSession.self) private var youtubeSession

    let playlist: Playlist

    @State private var store = PlaylistDetailStore()
    @State private var isShowingYouTubeWebPage = false

    var body: some View {
        content
            .background(Theme.background)
            .navigationTitle(playlist.title)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: playlist.id) {
                await store.load(playlistID: playlist.id)
            }
            .sheet(isPresented: $isShowingYouTubeWebPage) {
                NavigationStack {
                    YouTubeWebPageView(
                        title: "YouTube",
                        url: YouTubeWebPageView.homeURL
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.errorMessage,
                  store.videos.isEmpty {
            failureView(errorMessage)
        } else if store.hasLoaded && store.videos.isEmpty {
            RecoveryUnavailableView(
                RecoveryPresentation.make(
                    for: .emptyPlaylistVideos(playlistTitle: playlist.title)
                )
            )
        } else {
            videoList
        }
    }

    private var videoList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.videos) { video in
                    NavigationLink {
                        PlayerScreen(videoID: video.id)
                    } label: {
                        VideoCardView(video: video)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(.white.opacity(0.08))
                }

                playlistVideoContinuationView
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            await store.load(playlistID: playlist.id, force: true)
        }
    }

    @ViewBuilder
    private var playlistVideoContinuationView: some View {
        if store.continuation != nil {
            PaginationFooterView(
                isLoading: store.isLoadingMore,
                errorMessage: store.paginationErrorMessage
            ) {
                Task {
                    await loadMoreVideos()
                }
            }
                .task(id: store.continuation) {
                    guard store.paginationErrorMessage == nil else {
                        return
                    }

                    await loadMoreVideos()
                }
        }
    }

    private func failureView(_ message: String) -> some View {
        let issue = RecoveryPresentation.issueForPlaylistVideosFailure(message)
        let presentation = RecoveryPresentation.make(
            for: issue
        )

        return RecoveryUnavailableView(presentation) {
            VStack(spacing: 12) {
                if issue == .authExpired {
                    Button(presentation.primaryActionTitle ?? "Open YouTube Page") {
                        isShowingYouTubeWebPage = true
                    }

                    Button(presentation.secondaryActionTitle ?? "Retry") {
                        Task {
                            await store.load(playlistID: playlist.id, force: true)
                        }
                    }
                } else {
                    Button(presentation.primaryActionTitle ?? "Retry") {
                        Task {
                            await store.load(playlistID: playlist.id, force: true)
                        }
                    }
                }
            }
        }
    }

    private func loadMoreVideos() async {
        guard youtubeSession.isSignedIn else {
            return
        }

        do {
            let authContext = try await youtubeSession.refreshedAuthContext()
            await store.loadMore(authContext: authContext)
        } catch {
            store.failLoadingMore(with: error)
        }
    }
}
