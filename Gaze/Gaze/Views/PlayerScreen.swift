import AVFoundation
import Combine
import SwiftUI

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackStore.self) private var playbackStore
    @Environment(CaptionStore.self) private var captionStore

    private let source: PlayerSource

    @State private var player = AVPlayer(playerItem: nil)
    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var captionLoadTask: Task<Void, Never>?
    @State private var aspectRatioObservation: AnyCancellable?
    @State private var timeObserverToken: Any?
    @State private var loadError: String?
    @State private var videoAspectRatio = defaultAspectRatio
    @State private var qualityOptions: [PlayableQualityOption] = []
    @State private var selectedQualityID = PlaybackQualitySelection.highest.rawValue
    @State private var qualityLoadTask: Task<Void, Never>?
    @State private var hasCaptionTrack = false
    @State private var isQualityPickerPresented = false
    @State private var currentStream: Stream?

    init(url: URL = demoStreamURL) {
        self.source = .directURL(url)
    }

    init(videoID: String) {
        self.source = .youtubeVideoID(videoID)
    }

    var body: some View {
        ZStack {
            CenteredVideoPlayerView(
                player: player,
                aspectRatio: videoAspectRatio
            ) {
                ZStack {
                    VStack(spacing: 0) {
                        Spacer()

                        if playbackStore.captionsEnabled,
                           let text = captionStore.activeCaptionText {
                            CaptionOverlayView(text: text)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 14)
                        }
                    }
                    .padding(12)

                    if let loadError {
                        Text(loadError)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .padding(24)
                    }

                    if controlsVisible {
                        playerControls
                            .transition(.opacity)
                    }

                    if isQualityPickerPresented {
                        QualityPickerOverlayView(
                            options: qualityOptions,
                            selectedID: selectedQualityID,
                            onSelect: { option in
                                applyQuality(option)
                                dismissQualityPicker()
                            },
                            onDismiss: dismissQualityPicker
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onTapGesture {
            showControlsTemporarily()
        }
        .task(id: source) {
            await load(source)
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            isPlaying = status == .playing
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player.currentItem else {
                return
            }

            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            loadError = error?.localizedDescription
                ?? player.currentItem?.error?.localizedDescription
                ?? "Video playback failed."
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemNewErrorLogEntry)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player.currentItem,
                  let event = player.currentItem?.errorLog()?.events.last else {
                return
            }

            loadError = event.errorComment
                ?? event.errorStatusCode.description
        }
        .onAppear {
            player.appliesMediaSelectionCriteriaAutomatically = false
            player.play()
            showControlsTemporarily()
        }
        .onDisappear {
            controlsHideTask?.cancel()
            controlsHideTask = nil
            aspectRatioObservation?.cancel()
            aspectRatioObservation = nil
            qualityLoadTask?.cancel()
            qualityLoadTask = nil
            cancelCaptionLoad()
            removeCaptionTimeObserver()
            captionStore.clear()
            player.pause()
            isPlaying = false
        }
    }

    private var playerControls: some View {
        ZStack(alignment: .topLeading) {
            Button {
                player.pause()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.black.opacity(0.62), in: Circle())
            .accessibilityLabel("Back")
            .padding(.top, 18)
            .padding(.leading, 16)

            topRightControls

            HStack(spacing: 32) {
                Button {
                    seek(by: -10)
                    showControlsTemporarily()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 34, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Rewind 10 seconds")

                Button {
                    togglePlayback()
                    showControlsTemporarily()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button {
                    seek(by: 10)
                    showControlsTemporarily()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 34, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Forward 10 seconds")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.black.opacity(0.50), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topRightControls: some View {
        HStack(spacing: 12) {
            if currentStream != nil {
                Button {
                    showQualityPicker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3.weight(.semibold))

                        Text(qualityControlLabel)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 48)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.black.opacity(0.62), in: Capsule())
                .accessibilityLabel("Quality, \(qualityAccessibilityLabel)")
            }

            if hasCaptionTrack {
                Button {
                    playbackStore.setCaptionsEnabled(!playbackStore.captionsEnabled)
                    showControlsTemporarily()
                } label: {
                    Image(systemName: playbackStore.captionsEnabled ? "captions.bubble" : "captions.bubble.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .opacity(playbackStore.captionsEnabled ? 1.0 : 0.62)
                .background(.black.opacity(0.62), in: Circle())
                .accessibilityLabel(playbackStore.captionsEnabled ? "Hide Captions" : "Show Captions")
            }
        }
        .padding(.top, 18)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var qualityControlLabel: String {
        guard selectedQualityID == PlaybackQualitySelection.highest.rawValue else {
            return selectedQualityOption.map(qualitySummaryLabel) ?? "Quality"
        }

        if let highestAvailableQualityLabel {
            return "Auto \(highestAvailableQualityLabel)"
        }

        return "Auto"
    }

    private var qualityAccessibilityLabel: String {
        guard selectedQualityID == PlaybackQualitySelection.highest.rawValue else {
            return selectedQualityOption?.label ?? "Quality"
        }

        if let highestAvailableQualityLabel {
            return "Highest available, up to \(highestAvailableQualityLabel)"
        }

        return "Highest available"
    }

    private var selectedQualityOption: PlayableQualityOption? {
        qualityOptions.first { $0.id == selectedQualityID }
    }

    private var highestAvailableQualityLabel: String? {
        qualityOptions
            .first { $0.id != PlaybackQualitySelection.highest.rawValue }
            .map(qualitySummaryLabel)
    }

    private func qualitySummaryLabel(for option: PlayableQualityOption) -> String {
        if let height = option.height {
            if let frameRate = option.frameRate, frameRate >= 50 {
                return "\(height)p\(frameRate)"
            }

            return "\(height)p"
        }

        return option.label.replacingOccurrences(of: " HD", with: "")
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    private func seek(by seconds: Double) {
        let currentTime = player.currentTime().seconds
        guard currentTime.isFinite else {
            return
        }

        let targetTime = max(0, currentTime + seconds)
        player.seek(
            to: CMTime(seconds: targetTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func showControlsTemporarily() {
        controlsHideTask?.cancel()
        controlsHideTask = nil

        withAnimation(.easeInOut(duration: 0.16)) {
            controlsVisible = true
        }

        guard !isQualityPickerPresented else {
            return
        }

        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeOut(duration: 0.18)) {
                controlsVisible = false
            }

            controlsHideTask = nil
        }
    }

    private func showQualityPicker() {
        controlsHideTask?.cancel()
        controlsHideTask = nil

        withAnimation(.easeInOut(duration: 0.16)) {
            controlsVisible = true
            isQualityPickerPresented = true
        }
    }

    private func dismissQualityPicker() {
        withAnimation(.easeOut(duration: 0.16)) {
            isQualityPickerPresented = false
        }

        showControlsTemporarily()
    }

    private func load(_ source: PlayerSource) async {
        loadError = nil
        hasCaptionTrack = false
        isQualityPickerPresented = false
        currentStream = nil
        qualityOptions = []
        selectedQualityID = PlaybackQualitySelection.highest.rawValue
        qualityLoadTask?.cancel()
        qualityLoadTask = nil
        cancelCaptionLoad()
        captionStore.clear()
        installCaptionTimeObserver()

        do {
            try Task.checkCancellation()

            switch source {
            case .directURL(let url):
                replaceCurrentItem(AVPlayerItem(url: url))
                hasCaptionTrack = true
                startCaptionLoad(
                    demoCaptionTrack,
                    using: LocalCaptionCueService(vttText: demoCaptionVTT),
                    initialPlaybackTime: player.currentTime().seconds
                )
            case .youtubeVideoID(let videoID):
                try await loadYouTubeVideo(videoID: videoID)
            }

            try Task.checkCancellation()
            player.playImmediately(atRate: 1.0)
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }

            player.pause()
            player.replaceCurrentItem(with: nil)
            cancelCaptionLoad()
            captionStore.clear()
            loadError = error.localizedDescription
        }
    }

    private func installCaptionTimeObserver() {
        removeCaptionTimeObserver()

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            MainActor.assumeIsolated {
                captionStore.updateActiveCaption(at: time.seconds)
            }
        }
    }

    private func removeCaptionTimeObserver() {
        guard let timeObserverToken else {
            return
        }

        player.removeTimeObserver(timeObserverToken)
        self.timeObserverToken = nil
    }

    private func loadYouTubeVideo(videoID: String) async throws {
        try Task.checkCancellation()
        let response = try await YouTubeClient.shared.player(videoID: videoID)
        try Task.checkCancellation()
        try response.validatePlayableForPlayerScreen()

        let stream = try StreamExtractor.resolve(
            from: response,
            selection: playbackStore.preferredQualitySelection
        )
        try Task.checkCancellation()
        currentStream = stream
        selectedQualityID = stream.isHLS || playbackStore.preferredQualitySelection.isHighest
            ? PlaybackQualitySelection.highest.rawValue
            : playbackStore.preferredQualitySelection.rawValue
        replaceCurrentItem(makeYouTubePlayerItem(stream: stream))
        loadQualityOptions(for: stream, response: response)

        if let track = response.captionTracks.first {
            hasCaptionTrack = true
            startCaptionLoad(
                track,
                using: YouTubeCaptionService.shared,
                initialPlaybackTime: player.currentTime().seconds
            )
        } else {
            hasCaptionTrack = false
            captionStore.clear()
        }
    }

    private func loadQualityOptions(for stream: Stream, response: PlayerResponse) {
        qualityLoadTask?.cancel()

        qualityOptions = [highestQualityOption(for: stream)]

        if stream.isHLS {
            qualityLoadTask = Task { @MainActor in
                let options = await HLSVariantService.shared.qualityOptions(
                    for: stream,
                    userAgent: playbackUserAgent(for: stream)
                )

                guard !Task.isCancelled,
                      currentStream?.url == stream.url else {
                    return
                }

                qualityOptions = options
                applyPreferredQualitySelectionIfAvailable(in: options)
            }
        } else {
            let directOptions = StreamExtractor.playableMuxedQualityOptions(from: response)
            let highestDirectStream = directOptions.lazy.compactMap { option -> Stream? in
                guard case .directStream(let stream) = option.application else {
                    return nil
                }

                return stream
            }.first ?? stream

            qualityOptions = [highestQualityOption(for: highestDirectStream)]
                + directOptions

            if !qualityOptions.contains(where: { $0.id == selectedQualityID }) {
                selectedQualityID = PlaybackQualitySelection.highest.rawValue
            }
        }
    }

    private func highestQualityOption(for stream: Stream?) -> PlayableQualityOption {
        let application: PlaybackQualityApplication
        if let stream {
            application = stream.isHLS ? .hlsCap(nil) : .directStream(stream)
        } else {
            application = .hlsCap(nil)
        }
        let label = if let stream,
                       let summary = qualitySummaryLabel(for: stream) {
            "Highest available · up to \(summary)"
        } else {
            "Highest available"
        }

        return PlayableQualityOption(
            id: PlaybackQualitySelection.highest.rawValue,
            label: label,
            height: stream?.height,
            frameRate: stream?.fps,
            bitrate: stream?.bitrate,
            application: application
        )
    }

    private func qualitySummaryLabel(for stream: Stream) -> String? {
        if let height = stream.height {
            if let frameRate = stream.fps, frameRate >= 50 {
                return "\(height)p\(frameRate)"
            }

            return "\(height)p"
        }

        return stream.qualityLabel
    }

    private func applyQuality(
        _ option: PlayableQualityOption,
        shouldPersist: Bool = true
    ) {
        switch option.application {
        case .hlsCap(let cap):
            guard let currentItem = player.currentItem else {
                return
            }

            applyHLSCap(cap, to: currentItem)
            selectedQualityID = option.id
            if shouldPersist {
                playbackStore.setPreferredQualitySelection(PlaybackQualitySelection(rawValue: option.id))
            }

        case .directStream(let stream):
            let wasPlaying = isPlaying || player.timeControlStatus == .playing
            let currentTime = player.currentTime()
            let hasFiniteTime = currentTime.seconds.isFinite
            let item = makeYouTubePlayerItem(stream: stream)

            currentStream = stream
            selectedQualityID = option.id
            replaceCurrentItem(item)

            if shouldPersist {
                playbackStore.setPreferredQualitySelection(PlaybackQualitySelection(rawValue: option.id))
            }

            if hasFiniteTime {
                player.seek(
                    to: currentTime,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { _ in
                    guard wasPlaying else {
                        return
                    }

                    Task { @MainActor in
                        player.play()
                    }
                }
            } else if wasPlaying {
                player.play()
            }
        }
    }

    private func applyPreferredQualitySelectionIfAvailable(in options: [PlayableQualityOption]) {
        let preferredSelection = playbackStore.preferredQualitySelection
        guard !preferredSelection.isHighest else {
            selectedQualityID = PlaybackQualitySelection.highest.rawValue
            return
        }

        guard let option = options.first(where: { $0.id == preferredSelection.rawValue }) else {
            selectedQualityID = PlaybackQualitySelection.highest.rawValue
            return
        }

        applyQuality(option, shouldPersist: false)
    }

    private func startCaptionLoad<Service: CaptionCueFetching>(
        _ track: CaptionTrack,
        using service: Service,
        initialPlaybackTime: TimeInterval
    ) {
        cancelCaptionLoad()

        captionLoadTask = Task { @MainActor in
            await captionStore.loadTrack(
                track,
                using: service,
                initialPlaybackTime: initialPlaybackTime
            )
        }
    }

    private func cancelCaptionLoad() {
        captionLoadTask?.cancel()
        captionLoadTask = nil
    }

    private func replaceCurrentItem(_ item: AVPlayerItem) {
        aspectRatioObservation?.cancel()
        videoAspectRatio = Self.defaultAspectRatio
        player.replaceCurrentItem(with: item)
        observeAspectRatio(for: item)
    }

    private func observeAspectRatio(for item: AVPlayerItem) {
        aspectRatioObservation = item
            .publisher(for: \.presentationSize, options: [.initial, .new])
            .compactMap(Self.aspectRatio(from:))
            .removeDuplicates()
            .sink { aspectRatio in
                Task { @MainActor in
                    guard item === player.currentItem else {
                        return
                    }

                    videoAspectRatio = aspectRatio
                }
            }
    }

    private func makeYouTubePlayerItem(stream: Stream) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: stream.url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": playbackUserAgent(for: stream),
                ],
            ]
        )

        let item = AVPlayerItem(asset: asset)
        applyQualityPreferences(to: item, stream: stream)
        return item
    }

    private func applyQualityPreferences(to item: AVPlayerItem, stream: Stream) {
        guard stream.isHLS else {
            return
        }

        applyHLSCap(stream.hlsCap, to: item)
    }

    private func applyHLSCap(_ cap: HLSQualityCap?, to item: AVPlayerItem) {
        if let cap {
            item.preferredMaximumResolution = CGSize(
                width: CGFloat(cap.width),
                height: CGFloat(cap.height)
            )
            item.preferredPeakBitRate = cap.peakBitRate ?? 0
        } else {
            item.preferredMaximumResolution = .zero
            item.preferredPeakBitRate = 0
        }
    }

    private func playbackUserAgent(for stream: Stream) -> String {
        stream.playbackUserAgent ?? Self.youtubePlaybackUserAgent
    }

    private static let youtubePlaybackUserAgent = InnertubeContextProvider.iOSUserAgent
    private static let defaultAspectRatio = 16.0 / 9.0

    private nonisolated static func aspectRatio(from presentationSize: CGSize) -> CGFloat? {
        guard presentationSize.width > 0,
              presentationSize.height > 0 else {
            return nil
        }

        return presentationSize.width / presentationSize.height
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private enum PlayerSource: Hashable {
    case directURL(URL)
    case youtubeVideoID(String)
}

private extension PlayerResponse {
    func validatePlayableForPlayerScreen() throws {
        guard let status = playabilityStatus?.status else {
            throw YouTubeError.playabilityBlocked("missing playability status")
        }

        guard status == "OK" else {
            throw YouTubeError.playabilityBlocked(playabilityStatus?.reason ?? status)
        }
    }
}

private let demoStreamURL = URL(
    string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
)!

private let demoCaptionTrack = CaptionTrack(
    id: "demo-en",
    baseURL: URL(string: "https://www.youtube.com/api/timedtext?v=demo&lang=en")!,
    languageCode: "en",
    displayName: "English",
    isAutoGenerated: false
)

private let demoCaptionVTT = """
WEBVTT

00:00:00.500 --> 00:00:04.200
Big Buck Bunny finds a quiet place.

00:00:04.800 --> 00:00:08.200
The caption text is now parsed from WebVTT.

00:00:08.800 --> 00:00:12.400
Controls keep fading without moving the captions.

00:00:13.000 --> 00:00:16.800
Next: replace this local VTT with YouTube timedtext.
"""
