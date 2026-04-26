import Foundation
import Observation

@Observable
@MainActor
final class CaptionStore {
    private(set) var cues: [CaptionCue] = []
    private(set) var activeCaptionText: String?
    private(set) var loadState = CaptionLoadState.idle
    private(set) var parseError: String?
    private var activeCueIndex: Int?

    func loadVTT(_ text: String) {
        do {
            storeCues(try VTTParser.parse(text), initialPlaybackTime: 0)
            parseError = nil
        } catch {
            cues = []
            activeCueIndex = nil
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

            storeCues(fetchedCues, initialPlaybackTime: initialPlaybackTime)
        } catch {
            guard !Task.isCancelled else {
                return
            }

            cues = []
            activeCueIndex = nil
            activeCaptionText = nil
            loadState = .failed
            parseError = error.localizedDescription
        }
    }

    func updateActiveCaption(at playbackTime: TimeInterval) {
        guard playbackTime.isFinite, playbackTime >= 0 else {
            activeCueIndex = nil
            activeCaptionText = nil
            return
        }

        if let activeCueIndex,
           cues.indices.contains(activeCueIndex),
           cues[activeCueIndex].contains(playbackTime) {
            activeCaptionText = cues[activeCueIndex].text
            return
        }

        activeCueIndex = cueIndex(at: playbackTime)
        activeCaptionText = activeCueIndex.map { cues[$0].text }
    }

    func clear() {
        cues = []
        activeCueIndex = nil
        activeCaptionText = nil
        loadState = .idle
        parseError = nil
    }

    private func storeCues(_ newCues: [CaptionCue], initialPlaybackTime: TimeInterval) {
        cues = newCues.sorted { left, right in
            if left.startTime == right.startTime {
                left.endTime < right.endTime
            } else {
                left.startTime < right.startTime
            }
        }
        activeCueIndex = nil
        loadState = cues.isEmpty ? .unavailable : .ready
        updateActiveCaption(at: initialPlaybackTime)
    }

    private func cueIndex(at playbackTime: TimeInterval) -> Int? {
        var lowerBound = 0
        var upperBound = cues.count

        while lowerBound < upperBound {
            let midpoint = lowerBound + ((upperBound - lowerBound) / 2)
            if cues[midpoint].startTime <= playbackTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let candidateIndex = lowerBound - 1
        guard cues.indices.contains(candidateIndex),
              cues[candidateIndex].contains(playbackTime) else {
            return nil
        }

        return candidateIndex
    }
}

enum CaptionLoadState: Sendable {
    case idle
    case loading
    case ready
    case unavailable
    case failed
}
