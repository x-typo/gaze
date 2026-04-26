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
            ContentUnavailableView(
                "Sign In Required",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Use Settings to sign in to YouTube.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if playlistsStore.isLoading && !playlistsStore.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = playlistsStore.errorMessage,
                  playlistsStore.playlists.isEmpty {
            failureView(errorMessage)
        } else if playlistsStore.hasLoaded && playlistsStore.playlists.isEmpty {
            ContentUnavailableView(
                "No Playlists",
                systemImage: "list.bullet",
                description: Text("YouTube did not return any playlists for this account.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                errorMessage: playlistsStore.errorMessage
            ) {
                Task {
                    await loadMorePlaylists()
                }
            }
                .task(id: playlistsStore.continuation) {
                    guard playlistsStore.errorMessage == nil else {
                        return
                    }

                    await loadMorePlaylists()
                }
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Playlists Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 12) {
                Button("Retry") {
                    Task {
                        await loadPlaylists(force: true)
                    }
                }

                Button("Open YouTube Page") {
                    isShowingPlaylistWebPage = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
