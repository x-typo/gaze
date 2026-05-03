import Foundation
import Observation

@Observable
@MainActor
final class PlaybackStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let captionsEnabled = "gaze.playback.captionsEnabled"
        static let preferredQualitySelection = "gaze.playback.preferredQualitySelection"
    }

    private(set) var captionsEnabled: Bool
    private(set) var preferredQualitySelection: PlaybackQualitySelection

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.captionsEnabled) == nil {
            captionsEnabled = true
        } else {
            captionsEnabled = defaults.bool(forKey: Keys.captionsEnabled)
        }

        let storedQuality = defaults.string(forKey: Keys.preferredQualitySelection) ?? ""
        preferredQualitySelection = storedQuality.isEmpty
            ? .highest
            : PlaybackQualitySelection(rawValue: storedQuality)
    }

    func setCaptionsEnabled(_ isEnabled: Bool) {
        captionsEnabled = isEnabled
        defaults.set(isEnabled, forKey: Keys.captionsEnabled)
    }

    func setPreferredQualitySelection(_ selection: PlaybackQualitySelection) {
        preferredQualitySelection = selection
        defaults.set(selection.rawValue, forKey: Keys.preferredQualitySelection)
    }
}
