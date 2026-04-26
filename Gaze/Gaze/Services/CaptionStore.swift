import Foundation
import Observation

@Observable
@MainActor
final class CaptionStore {
    private(set) var cues: [CaptionCue] = []
    private(set) var activeCaptionText: String?
    private(set) var loadState = CaptionLoadState.idle
    private(set) var parseError: String?

    func loadVTT(_ text: String) {
        do {
            cues = try VTTParser.parse(text)
            loadState = cues.isEmpty ? .unavailable : .ready
            parseError = nil
            updateActiveCaption(at: 0)
        } catch {
            cues = []
            activeCaptionText = nil
            loadState = .failed
            parseError = error.localizedDescription
        }
    }

    func loadTrack(
        _ track: CaptionTrack,
        using service: any CaptionCueFetching,
        initialPlaybackTime: TimeInterval = 0
    ) async {
        loadState = .loading
        parseError = nil

        do {
            let fetchedCues = try await service.fetchCues(for: track)
            guard !Task.isCancelled else {
                return
            }

            cues = fetchedCues
            loadState = cues.isEmpty ? .unavailable : .ready
            updateActiveCaption(at: initialPlaybackTime)
        } catch {
            guard !Task.isCancelled else {
                return
            }

            cues = []
            activeCaptionText = nil
            loadState = .failed
            parseError = error.localizedDescription
        }
    }

    func updateActiveCaption(at playbackTime: TimeInterval) {
        guard playbackTime.isFinite, playbackTime >= 0 else {
            activeCaptionText = nil
            return
        }

        activeCaptionText = cue(at: playbackTime)?.text
    }

    func clear() {
        cues = []
        activeCaptionText = nil
        loadState = .idle
        parseError = nil
    }

    private func cue(at playbackTime: TimeInterval) -> CaptionCue? {
        cues.first { $0.contains(playbackTime) }
    }
}

enum CaptionLoadState: Sendable {
    case idle
    case loading
    case ready
    case unavailable
    case failed
}
