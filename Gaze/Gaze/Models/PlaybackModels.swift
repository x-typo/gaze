import Foundation

nonisolated struct PlaybackQualitySelection: RawRepresentable, Hashable, Sendable {
    static let highest = PlaybackQualitySelection(rawValue: "highest")

    let rawValue: String

    var isHighest: Bool {
        rawValue == Self.highest.rawValue
    }
}

nonisolated struct HLSQualityCap: Hashable, Sendable {
    let width: Int
    let height: Int
    let peakBitRate: Double?
}

nonisolated enum PlaybackQualityApplication: Sendable {
    case hlsCap(HLSQualityCap?)
    case directStream(Stream)
}

nonisolated struct PlayableQualityOption: Identifiable, Sendable {
    let id: String
    let label: String
    let height: Int?
    let frameRate: Int?
    let bitrate: Int?
    let application: PlaybackQualityApplication
}
