import SwiftUI

struct PlaylistsView: View {
    @Environment(YouTubeSession.self) private var youtubeSession
    @Environment(PlaylistsStore.self) private var playlistsStore
    @State private var isShowingPlaylistWebPage = false

    var body: some View {
        content
            .background(Theme.background)
            .navigationTitle("Playlists")
            .task(id: youtubeSession.isSignedIn) {
                await loadPlaylists()
            }
            .sheet(isPresented: $isShowingPlaylistWebPage) {
                NavigationStack {
                    YouTubeWebPageView(
                        title: "YouTube Playlists",
                        url: YouTubeWebPageView.playlistsURL
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !youtubeSession.isSignedIn {
            RecoveryUnavailableView(RecoveryPresentation.make(for: .signedOut))
        } else if playlistsStore.isLoading && !playlistsStore.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = playlistsStore.errorMessage,
                  playlistsStore.playlists.isEmpty {
            failureView(errorMessage)
        } else if playlistsStore.hasLoaded && playlistsStore.playlists.isEmpty {
            RecoveryUnavailableView(RecoveryPresentation.make(for: .emptyPlaylists))
        } else {
            playlistList
        }
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(playlistsStore.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        PlaylistCardView(playlist: playlist)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(.white.opacity(0.08))
                }

                playlistContinuationView
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            await loadPlaylists(force: true)
        }
    }

    @ViewBuilder
    private var playlistContinuationView: some View {
        if playlistsStore.continuation != nil {
            PaginationFooterView(
                isLoading: playlistsStore.isLoadingMore,
                errorMessage: playlistsStore.paginationErrorMessage
            ) {
                Task {
                    await loadMorePlaylists()
                }
            }
                .task(id: playlistsStore.continuation) {
                    guard playlistsStore.paginationErrorMessage == nil else {
                        return
                    }

                    await loadMorePlaylists()
                }
        }
    }

    private func failureView(_ message: String) -> some View {
        let issue = RecoveryPresentation.issueForPlaylistsFailure(message)
        let presentation = RecoveryPresentation.make(for: issue)

        return RecoveryUnavailableView(presentation) {
            VStack(spacing: 12) {
                if issue == .authExpired {
                    Button(presentation.primaryActionTitle ?? "Open YouTube Page") {
                        isShowingPlaylistWebPage = true
                    }

                    Button(presentation.secondaryActionTitle ?? "Retry") {
                        Task {
                            await loadPlaylists(force: true)
                        }
                    }
                } else {
                    Button(presentation.primaryActionTitle ?? "Retry") {
                        Task {
                            await loadPlaylists(force: true)
                        }
                    }

                    if let secondaryActionTitle = presentation.secondaryActionTitle {
                        Button(secondaryActionTitle) {
                            isShowingPlaylistWebPage = true
                        }
                    }
                }
            }
        }
    }

    private func loadPlaylists(force: Bool = false) async {
        guard youtubeSession.isSignedIn else {
            playlistsStore.reset()
            return
        }

        do {
            let authContext = try await youtubeSession.refreshedPlaylistAuthContext()
            await playlistsStore.load(authContext: authContext, force: force)
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            playlistsStore.fail(with: error)
        }
    }

    private func loadMorePlaylists() async {
        guard youtubeSession.isSignedIn else {
            return
        }

        do {
            let authContext = try await youtubeSession.refreshedAuthContext()
            await playlistsStore.loadMore(authContext: authContext)
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            playlistsStore.failLoadingMore(with: error)
        }
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
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

private struct PlaylistCardView: View {
    let playlist: Playlist

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let videoCountText = playlist.videoCountText {
                    Text(videoCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        AsyncImage(url: playlist.thumbnailURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .overlay {
                        ProgressView()
                    }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholderThumbnail
            @unknown default:
                placeholderThumbnail
            }
        }
        .frame(width: 132, height: 74)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholderThumbnail: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .overlay {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}
