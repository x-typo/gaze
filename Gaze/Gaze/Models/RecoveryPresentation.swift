nonisolated struct RecoveryPresentation: Equatable {
    let title: String
    let systemImage: String
    let message: String
    let primaryActionTitle: String?
    let secondaryActionTitle: String?
}

nonisolated enum RecoveryIssue: Equatable {
    case signedOut
    case authExpired
    case emptyPlaylists
    case emptyPlaylistVideos(playlistTitle: String)
    case emptySearch(query: String)
    case playlistsFailure(message: String)
    case playlistVideosFailure(message: String)
    case searchFailure(message: String)
    case paginationFailure(message: String)
}

extension RecoveryPresentation {
    static func make(for issue: RecoveryIssue) -> RecoveryPresentation {
        switch issue {
        case .signedOut:
            RecoveryPresentation(
                title: "Sign in to YouTube",
                systemImage: "person.crop.circle.badge.exclamationmark",
                message: "Gaze needs your YouTube session to load playlists.",
                primaryActionTitle: nil,
                secondaryActionTitle: nil
            )
        case .authExpired:
            RecoveryPresentation(
                title: "Sign in again",
                systemImage: "person.crop.circle.badge.exclamationmark",
                message: "YouTube rejected the saved session. Open YouTube and sign in again.",
                primaryActionTitle: "Open YouTube Page",
                secondaryActionTitle: "Retry"
            )
        case .emptyPlaylists:
            RecoveryPresentation(
                title: "No Playlists",
                systemImage: "list.bullet.rectangle",
                message: "This YouTube account did not return any playlists.",
                primaryActionTitle: nil,
                secondaryActionTitle: nil
            )
        case .emptyPlaylistVideos:
            RecoveryPresentation(
                title: "No Videos",
                systemImage: "play.rectangle",
                message: "YouTube did not return any videos for this playlist.",
                primaryActionTitle: nil,
                secondaryActionTitle: nil
            )
        case .emptySearch(let query):
            RecoveryPresentation(
                title: "No Results",
                systemImage: "magnifyingglass",
                message: emptySearchMessage(query: query),
                primaryActionTitle: nil,
                secondaryActionTitle: nil
            )
        case .playlistsFailure:
            RecoveryPresentation(
                title: "Playlists Failed",
                systemImage: "exclamationmark.triangle",
                message: "Gaze could not load playlists from YouTube. Try again in a moment.",
                primaryActionTitle: "Retry",
                secondaryActionTitle: "Open YouTube Page"
            )
        case .playlistVideosFailure:
            RecoveryPresentation(
                title: "Playlist Failed",
                systemImage: "exclamationmark.triangle",
                message: "Gaze could not load this playlist from YouTube. Try again in a moment.",
                primaryActionTitle: "Retry",
                secondaryActionTitle: nil
            )
        case .searchFailure:
            RecoveryPresentation(
                title: "Search Failed",
                systemImage: "exclamationmark.triangle",
                message: "Gaze could not search YouTube. Try again in a moment.",
                primaryActionTitle: "Retry",
                secondaryActionTitle: nil
            )
        case .paginationFailure:
            RecoveryPresentation(
                title: "More Items Failed",
                systemImage: "exclamationmark.circle",
                message: "Gaze could not load the next page.",
                primaryActionTitle: "Retry",
                secondaryActionTitle: nil
            )
        }
    }

    static func issueForPlaylistsFailure(_ message: String) -> RecoveryIssue {
        isAuthExpiredMessage(message) ? .authExpired : .playlistsFailure(message: message)
    }

    static func issueForPlaylistVideosFailure(_ message: String) -> RecoveryIssue {
        isAuthExpiredMessage(message) ? .authExpired : .playlistVideosFailure(message: message)
    }

    static func issueForSearchFailure(_ message: String) -> RecoveryIssue {
        isAuthExpiredMessage(message) ? .authExpired : .searchFailure(message: message)
    }

    static func isAuthExpiredMessage(_ message: String) -> Bool {
        let normalizedMessage = message.lowercased()
        return [
            "missing youtube auth cookie",
            "http 401",
            "http 403",
            "youtube rejected the stored session",
            "sign in again",
        ].contains { normalizedMessage.contains($0) }
    }

    private static func emptySearchMessage(query: String) -> String {
        guard !query.isEmpty else {
            return "No YouTube videos matched this search."
        }

        return "No YouTube videos matched \"\(query)\"."
    }
}
