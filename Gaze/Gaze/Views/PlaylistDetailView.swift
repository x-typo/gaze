import SwiftUI

struct PlaylistDetailView: View {
    @Environment(YouTubeSession.self) private var youtubeSession

    let playlist: Playlist

    @State private var store = PlaylistDetailStore()

    var body: some View {
        content
            .background(Theme.background)
            .navigationTitle(playlist.title)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: playlist.id) {
                await store.load(playlistID: playlist.id)
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
            ContentUnavailableView(
                "No Videos",
                systemImage: "play.rectangle",
                description: Text("YouTube did not return any videos for this playlist.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ProgressView()
                .padding(.vertical, 20)
                .task(id: store.continuation) {
                    await loadMoreVideos()
                }
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Playlist Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task {
                    await store.load(playlistID: playlist.id, force: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadMoreVideos() async {
        guard youtubeSession.isSignedIn else {
            return
        }

        do {
            let authContext = try await youtubeSession.refreshedPlaylistAuthContext()
            await store.loadMore(authContext: authContext)
        } catch {
            store.failLoadingMore(with: error)
        }
    }
}
