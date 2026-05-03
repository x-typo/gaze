import AVFoundation
import Foundation

actor HLSVariantService {
    static let shared = HLSVariantService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func qualityOptions(for stream: Stream, userAgent: String) async -> [PlayableQualityOption] {
        guard stream.isHLS else {
            return []
        }

        if let manifestOptions = try? await manifestQualityOptions(
            for: stream,
            userAgent: userAgent
        ), !manifestOptions.isEmpty {
            return [Self.highestOption(for: stream, maxOption: manifestOptions.first)] + manifestOptions
        }

        do {
            let asset = AVURLAsset(
                url: stream.url,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "User-Agent": userAgent,
                    ],
                ]
            )
            let variants = try await asset.load(.variants)
            let variantOptions = qualityOptions(from: variants)

            guard !variantOptions.isEmpty else {
                return [Self.highestOption(for: stream, maxOption: nil)]
            }

            return [Self.highestOption(for: stream, maxOption: variantOptions.first)] + variantOptions
        } catch {
            return [Self.highestOption(for: stream, maxOption: nil)]
        }
    }

    private func manifestQualityOptions(
        for stream: Stream,
        userAgent: String
    ) async throws -> [PlayableQualityOption] {
        var request = URLRequest(url: stream.url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw HLSVariantServiceError.invalidResponse
        }

        guard let manifest = String(data: data, encoding: .utf8) else {
            throw HLSVariantServiceError.invalidUTF8
        }

        return qualityOptions(fromMasterManifest: manifest)
    }

    private func qualityOptions(
        fromMasterManifest manifest: String
    ) -> [PlayableQualityOption] {
        let lines = manifest.components(separatedBy: .newlines)
        var optionsByQuality = [String: PlayableQualityOption]()

        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("#EXT-X-STREAM-INF:"),
                  let resolution = resolution(in: line),
                  Self.isSelectableManualQuality(height: resolution.height),
                  hasVariantURI(after: index, in: lines) else {
                continue
            }

            let frameRate = attributeDouble("FRAME-RATE", in: line).map { Int($0.rounded()) }
            let bitRate = attributeInt("BANDWIDTH", in: line)
            let label = optionLabel(height: resolution.height, frameRate: frameRate)
            let id = optionID(height: resolution.height, frameRate: frameRate)
            let cap = HLSQualityCap(
                width: resolution.width,
                height: resolution.height,
                peakBitRate: bitRate.map(Double.init)
            )
            let option = PlayableQualityOption(
                id: id,
                label: label,
                height: resolution.height,
                frameRate: frameRate,
                bitrate: bitRate,
                application: .hlsCap(cap)
            )

            guard let existing = optionsByQuality[id] else {
                optionsByQuality[id] = option
                continue
            }

            if (option.bitrate ?? 0) > (existing.bitrate ?? 0) {
                optionsByQuality[id] = option
            }
        }

        return sortedQualityOptions(optionsByQuality.values)
    }

    private func qualityOptions(from variants: [AVAssetVariant]) -> [PlayableQualityOption] {
        var optionsByQuality = [String: PlayableQualityOption]()

        for variant in variants {
            guard let videoAttributes = variant.videoAttributes else {
                continue
            }

            let presentationSize = videoAttributes.presentationSize
            let width = Int(presentationSize.width.rounded())
            let height = Int(presentationSize.height.rounded())
            guard width > 0,
                  height > 0,
                  Self.isSelectableManualQuality(height: height) else {
                continue
            }

            let frameRate = videoAttributes.nominalFrameRate.map { Int($0.rounded()) }
            let bitRate = variant.peakBitRate ?? variant.averageBitRate
            let option = PlayableQualityOption(
                id: optionID(height: height, frameRate: frameRate),
                label: optionLabel(height: height, frameRate: frameRate),
                height: height,
                frameRate: frameRate,
                bitrate: bitRate.map(Int.init),
                application: .hlsCap(
                    HLSQualityCap(
                        width: width,
                        height: height,
                        peakBitRate: bitRate
                    )
                )
            )

            let key = optionID(height: height, frameRate: frameRate)
            guard let existing = optionsByQuality[key] else {
                optionsByQuality[key] = option
                continue
            }

            if (option.bitrate ?? 0) > (existing.bitrate ?? 0) {
                optionsByQuality[key] = option
            }
        }

        return sortedQualityOptions(optionsByQuality.values)
    }

    private nonisolated func sortedQualityOptions(
        _ options: Dictionary<String, PlayableQualityOption>.Values
    ) -> [PlayableQualityOption] {
        sortedQualityOptions(Array(options))
    }

    private nonisolated func sortedQualityOptions(_ options: [PlayableQualityOption]) -> [PlayableQualityOption] {
        options.sorted { left, right in
            let leftRank = [
                left.height ?? 0,
                left.frameRate ?? 0,
                left.bitrate ?? 0,
            ]
            let rightRank = [
                right.height ?? 0,
                right.frameRate ?? 0,
                right.bitrate ?? 0,
            ]

            return leftRank.lexicographicallyPrecedes(rightRank) == false
                && leftRank != rightRank
        }
    }

    private nonisolated static func highestOption(
        for stream: Stream,
        maxOption: PlayableQualityOption?
    ) -> PlayableQualityOption {
        let maxLabel = maxOption.flatMap(qualitySummaryLabel(for:))
        let label = if let maxLabel {
            "Highest available · up to \(maxLabel)"
        } else {
            "Highest available"
        }

        return PlayableQualityOption(
            id: PlaybackQualitySelection.highest.rawValue,
            label: label,
            height: maxOption?.height,
            frameRate: maxOption?.frameRate,
            bitrate: maxOption?.bitrate,
            application: stream.isHLS ? .hlsCap(nil) : .directStream(stream)
        )
    }

    private nonisolated static func qualitySummaryLabel(for option: PlayableQualityOption) -> String? {
        if let height = option.height {
            if let frameRate = option.frameRate, frameRate >= 50 {
                return "\(height)p\(frameRate)"
            }

            return "\(height)p"
        }

        return option.label.isEmpty ? nil : option.label
    }

    private nonisolated static func isSelectableManualQuality(height: Int) -> Bool {
        height >= 240
    }

    private nonisolated func hasVariantURI(
        after index: [String].Index,
        in lines: [String]
    ) -> Bool {
        var nextIndex = lines.index(after: index)
        while nextIndex < lines.endIndex {
            let uri = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if !uri.isEmpty, !uri.hasPrefix("#") {
                return true
            }

            nextIndex = lines.index(after: nextIndex)
        }

        return false
    }

    private nonisolated func resolution(in line: String) -> (width: Int, height: Int)? {
        guard let match = firstMatch(
            in: line,
            pattern: #"RESOLUTION=(\d+)x(\d+)"#,
            groups: 2
        ), let width = Int(match[0]), let height = Int(match[1]),
           width > 0, height > 0 else {
            return nil
        }

        return (width, height)
    }

    private nonisolated func attributeInt(_ name: String, in line: String) -> Int? {
        firstMatch(
            in: line,
            pattern: "\(NSRegularExpression.escapedPattern(for: name))=(\\d+)",
            groups: 1
        ).flatMap { Int($0[0]) }
    }

    private nonisolated func attributeDouble(_ name: String, in line: String) -> Double? {
        firstMatch(
            in: line,
            pattern: "\(NSRegularExpression.escapedPattern(for: name))=([0-9]+(?:\\.[0-9]+)?)",
            groups: 1
        ).flatMap { Double($0[0]) }
    }

    private nonisolated func firstMatch(
        in text: String,
        pattern: String,
        groups: Int
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        var values = [String]()
        for group in 1...groups {
            guard let groupRange = Range(match.range(at: group), in: text) else {
                return nil
            }

            values.append(String(text[groupRange]))
        }

        return values
    }

    private nonisolated func optionID(height: Int, frameRate: Int?) -> String {
        if let frameRate {
            return "hls-\(height)-\(frameRate)"
        }

        return "hls-\(height)"
    }

    private nonisolated func optionLabel(height: Int, frameRate: Int?) -> String {
        let baseLabel: String
        if let frameRate, frameRate >= 50 {
            baseLabel = "\(height)p\(frameRate)"
        } else {
            baseLabel = "\(height)p"
        }

        if height >= 720 {
            return "\(baseLabel) HD"
        }

        return baseLabel
    }
}

private nonisolated enum HLSVariantServiceError: Error {
    case invalidResponse
    case invalidUTF8
}
