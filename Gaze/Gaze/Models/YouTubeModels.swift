import Foundation

nonisolated struct Video: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let channelTitle: String?
    let durationText: String?
    let viewCountText: String?
    let publishedText: String?
    let thumbnailURL: URL?
}

nonisolated struct SearchPage: Sendable {
    let videos: [Video]
    let continuation: String?
}

nonisolated struct Playlist: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let videoCountText: String?
    let thumbnailURL: URL?
}

nonisolated struct PlaylistPage: Sendable {
    let playlists: [Playlist]
    let continuation: String?
}

nonisolated struct PlaylistVideoPage: Sendable {
    let videos: [Video]
    let continuation: String?
}

nonisolated struct AuthProbeResult: Sendable {
    let responseByteCount: Int
}

nonisolated struct NativePageProbeResult: Sendable {
    let responseByteCount: Int
    let finalHost: String?
    let finalPath: String?
    let wasRedirectedToSignIn: Bool
}

nonisolated struct YouTubeAuthContext: Sendable {
    let sapisid: String
    let cookieHeader: String
    let nativePageCookieHeader: String
}
