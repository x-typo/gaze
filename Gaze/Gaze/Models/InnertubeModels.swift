import Foundation

nonisolated struct InnertubeContext: Encodable, Sendable {
    let client: InnertubeClientContext
    let user = InnertubeUserContext()
    let request = InnertubeRequestContext()
}

nonisolated struct InnertubeClientContext: Encodable, Sendable {
    let clientName: String
    let clientVersion: String
    let hl: String
    let gl: String
    let visitorData: String?
    let deviceMake: String?
    let deviceModel: String?
    let androidSdkVersion: Int?
    let userAgent: String?
    let osName: String?
    let osVersion: String?

    init(
        clientName: String,
        clientVersion: String,
        hl: String,
        gl: String,
        visitorData: String?,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        androidSdkVersion: Int? = nil,
        userAgent: String? = nil,
        osName: String? = nil,
        osVersion: String? = nil
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.hl = hl
        self.gl = gl
        self.visitorData = visitorData
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.androidSdkVersion = androidSdkVersion
        self.userAgent = userAgent
        self.osName = osName
        self.osVersion = osVersion
    }
}

nonisolated struct InnertubeUserContext: Encodable, Sendable {
    let lockedSafetyMode = false
}

nonisolated struct InnertubeRequestContext: Encodable, Sendable {
    let useSsl = true
}

nonisolated struct PlayerRequestPayload: Encodable, Sendable {
    let context: InnertubeContext
    let videoID: String
    let contentCheckOk = true
    let racyCheckOk = true

    private enum CodingKeys: String, CodingKey {
        case context
        case videoID = "videoId"
        case contentCheckOk
        case racyCheckOk
    }
}

nonisolated struct SearchRequestPayload: Encodable, Sendable {
    let context: InnertubeContext
    let query: String?
    let continuation: String?

    init(
        context: InnertubeContext,
        query: String? = nil,
        continuation: String? = nil
    ) {
        self.context = context
        self.query = query
        self.continuation = continuation
    }
}

nonisolated struct BrowseRequestPayload: Encodable, Sendable {
    let context: InnertubeContext
    let browseID: String?
    let continuation: String?

    init(
        context: InnertubeContext,
        browseID: String? = nil,
        continuation: String? = nil
    ) {
        self.context = context
        self.browseID = browseID
        self.continuation = continuation
    }

    private enum CodingKeys: String, CodingKey {
        case context
        case browseID = "browseId"
        case continuation
    }
}

nonisolated struct AccountsListRequestPayload: Encodable, Sendable {
    let context: InnertubeContext
}

nonisolated struct PlayerResponse: Decodable, Sendable {
    let playabilityStatus: PlayabilityStatus?
    let streamingData: StreamingData?
    let videoDetails: VideoDetails?
    let captions: PlayerCaptions?
    let playbackUserAgent: String?

    var captionTracks: [CaptionTrack] {
        captions?.playerCaptionsTracklistRenderer?.captionTracks.map(\.captionTrack) ?? []
    }

    func withPlaybackUserAgent(_ userAgent: String) -> PlayerResponse {
        PlayerResponse(
            playabilityStatus: playabilityStatus,
            streamingData: streamingData,
            videoDetails: videoDetails,
            captions: captions,
            playbackUserAgent: userAgent
        )
    }
}

nonisolated struct PlayabilityStatus: Decodable, Sendable {
    let status: String
    let reason: String?
}

nonisolated struct StreamingData: Decodable, Sendable {
    let expiresInSeconds: String?
    let formats: [StreamFormat]?
    let adaptiveFormats: [StreamFormat]?
    let hlsManifestURL: URL?

    private enum CodingKeys: String, CodingKey {
        case expiresInSeconds
        case formats
        case adaptiveFormats
        case hlsManifestURL = "hlsManifestUrl"
    }
}

nonisolated struct StreamFormat: Decodable, Sendable {
    let itag: Int
    let url: URL?
    let mimeType: String
    let bitrate: Int?
    let qualityLabel: String?
    let audioQuality: String?
    let signatureCipher: String?
    let width: Int?
    let height: Int?
    let fps: Int?

    var isDirectMuxedMP4: Bool {
        url != nil
            && signatureCipher == nil
            && mimeType.lowercased().contains("video/mp4")
            && audioQuality != nil
    }
}

nonisolated struct VideoDetails: Decodable, Sendable {
    let videoID: String?
    let title: String?
    let author: String?
    let lengthSeconds: String?

    private enum CodingKeys: String, CodingKey {
        case videoID = "videoId"
        case title
        case author
        case lengthSeconds
    }
}

nonisolated struct Stream: Sendable {
    let id: String
    let url: URL
    let mimeType: String
    let isHLS: Bool
    let qualityLabel: String?
    let width: Int?
    let height: Int?
    let fps: Int?
    let bitrate: Int?
    let hlsCap: HLSQualityCap?
    let playbackUserAgent: String?
}
