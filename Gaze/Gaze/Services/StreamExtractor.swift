import Foundation

nonisolated enum StreamExtractor {
    static func canResolve(from response: PlayerResponse) -> Bool {
        guard let streamingData = response.streamingData else {
            return false
        }

        let formats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])
        return bestMuxedFormat(from: formats) != nil
            || streamingData.hlsManifestURL != nil
    }

    static func resolve(from response: PlayerResponse) throws -> Stream {
        guard let streamingData = response.streamingData else {
            throw YouTubeError.streamUnsupported("missing streaming data")
        }

        let formats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])
        if let format = bestMuxedFormat(from: formats),
           let url = format.url {
            return Stream(
                url: url,
                mimeType: format.mimeType,
                isHLS: false,
                qualityLabel: format.qualityLabel
            )
        }

        if let hlsManifestURL = streamingData.hlsManifestURL {
            return Stream(
                url: hlsManifestURL,
                mimeType: "application/x-mpegURL",
                isHLS: true,
                qualityLabel: "Auto"
            )
        }

        if formats.contains(where: { $0.signatureCipher != nil }) {
            throw YouTubeError.streamUnsupported("signed URL")
        }

        throw YouTubeError.streamUnsupported("no HLS or muxed MP4 format")
    }

    private static func bestMuxedFormat(from formats: [StreamFormat]) -> StreamFormat? {
        let muxedFormats = formats.filter(\.isDirectMuxedMP4)

        if let preferred720p = muxedFormats.first(where: { $0.itag == 22 }) {
            return preferred720p
        }

        if let preferred360p = muxedFormats.first(where: { $0.itag == 18 }) {
            return preferred360p
        }

        return muxedFormats.max { left, right in
            (left.bitrate ?? 0) < (right.bitrate ?? 0)
        }
    }
}
