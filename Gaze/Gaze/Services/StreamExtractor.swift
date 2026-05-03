import Foundation

nonisolated enum StreamExtractor {
    static func canResolve(from response: PlayerResponse) -> Bool {
        guard let streamingData = response.streamingData else {
            return false
        }

        let formats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])
        return supportedHLSManifestURL(from: response) != nil
            || highestMuxedFormat(from: formats) != nil
    }

    static func resolve(from response: PlayerResponse) throws -> Stream {
        try resolve(from: response, selection: .highest)
    }

    static func resolve(
        from response: PlayerResponse,
        selection: PlaybackQualitySelection
    ) throws -> Stream {
        guard let streamingData = response.streamingData else {
            throw YouTubeError.streamUnsupported("missing streaming data")
        }

        let formats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])
        if let hlsManifestURL = supportedHLSManifestURL(from: response) {
            return hlsStream(
                url: hlsManifestURL,
                playbackUserAgent: response.playbackUserAgent
            )
        }

        let muxedFormats = formats.filter(\.isDirectMuxedMP4)
        let selectedFormat = selection.isHighest
            ? nil
            : muxedFormats.first { streamID(for: $0) == selection.rawValue }

        if let format = selectedFormat ?? highestMuxedFormat(from: muxedFormats),
           let stream = muxedStream(
            from: format,
            playbackUserAgent: response.playbackUserAgent
           ) {
            return stream
        }

        if formats.contains(where: { $0.signatureCipher != nil }) {
            throw YouTubeError.streamUnsupported("signed URL")
        }

        throw YouTubeError.streamUnsupported("no HLS or direct muxed MP4 format")
    }

    static func playableMuxedQualityOptions(from response: PlayerResponse) -> [PlayableQualityOption] {
        guard let streamingData = response.streamingData else {
            return []
        }

        let formats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])
        return uniqueHighestMuxedFormats(from: formats).compactMap { format in
            guard let stream = muxedStream(
                from: format,
                playbackUserAgent: response.playbackUserAgent
            ) else {
                return nil
            }

            return PlayableQualityOption(
                id: stream.id,
                label: qualityLabel(for: format),
                height: format.height,
                frameRate: format.fps,
                bitrate: format.bitrate,
                application: .directStream(stream)
            )
        }
    }

    static func hasSupportedHLSStream(from response: PlayerResponse) -> Bool {
        supportedHLSManifestURL(from: response) != nil
    }

    private static func supportedHLSManifestURL(from response: PlayerResponse) -> URL? {
        guard let hlsManifestURL = response.streamingData?.hlsManifestURL else {
            return nil
        }

        // YouTube web HLS manifests with an /n/ challenge need player-JS rewriting.
        // Without that rewrite, media segments return 403 even when playlists load.
        guard !hlsManifestURL.path.contains("/n/") else {
            return nil
        }

        return hlsManifestURL
    }

    private static func hlsStream(url: URL, playbackUserAgent: String?) -> Stream {
        Stream(
            id: PlaybackQualitySelection.highest.rawValue,
            url: url,
            mimeType: "application/x-mpegURL",
            isHLS: true,
            qualityLabel: "Auto",
            width: nil,
            height: nil,
            fps: nil,
            bitrate: nil,
            hlsCap: nil,
            playbackUserAgent: playbackUserAgent
        )
    }

    private static func muxedStream(
        from format: StreamFormat,
        playbackUserAgent: String? = nil
    ) -> Stream? {
        guard let url = format.url else {
            return nil
        }

        return Stream(
            id: streamID(for: format),
            url: url,
            mimeType: format.mimeType,
            isHLS: false,
            qualityLabel: format.qualityLabel,
            width: format.width,
            height: format.height,
            fps: format.fps,
            bitrate: format.bitrate,
            hlsCap: nil,
            playbackUserAgent: playbackUserAgent
        )
    }

    private static func highestMuxedFormat(from formats: [StreamFormat]) -> StreamFormat? {
        formats
            .filter(\.isDirectMuxedMP4)
            .sorted(by: isHigherQuality)
            .first
    }

    private static func uniqueHighestMuxedFormats(from formats: [StreamFormat]) -> [StreamFormat] {
        let muxedFormats = formats.filter(\.isDirectMuxedMP4)
        var formatsByQuality = [String: StreamFormat]()

        for format in muxedFormats {
            let key = qualityKey(for: format)
            guard let existing = formatsByQuality[key] else {
                formatsByQuality[key] = format
                continue
            }

            if isHigherQuality(format, than: existing) {
                formatsByQuality[key] = format
            }
        }

        return formatsByQuality.values.sorted(by: isHigherQuality)
    }

    private static func qualityKey(for format: StreamFormat) -> String {
        if let height = format.height,
           let fps = format.fps {
            return "\(height)-\(fps)"
        }

        return streamID(for: format)
    }

    private static func streamID(for format: StreamFormat) -> String {
        "muxed-itag-\(format.itag)"
    }

    private static func isHigherQuality(_ left: StreamFormat, than right: StreamFormat) -> Bool {
        let leftRank = [
            left.height ?? 0,
            left.fps ?? 0,
            left.bitrate ?? 0,
        ]
        let rightRank = [
            right.height ?? 0,
            right.fps ?? 0,
            right.bitrate ?? 0,
        ]

        return leftRank.lexicographicallyPrecedes(rightRank) == false
            && leftRank != rightRank
    }

    private static func qualityLabel(for format: StreamFormat) -> String {
        let baseLabel: String
        if let height = format.height {
            if let fps = format.fps, fps >= 50 {
                baseLabel = "\(height)p\(fps)"
            } else {
                baseLabel = "\(height)p"
            }
        } else {
            baseLabel = format.qualityLabel ?? "Unknown"
        }

        if let height = format.height, height >= 720 {
            return "\(baseLabel) HD"
        }

        return baseLabel
    }
}
