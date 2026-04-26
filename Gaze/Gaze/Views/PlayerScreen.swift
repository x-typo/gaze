import AVFoundation
import Combine
import SwiftUI

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CaptionStore.self) private var captionStore

    private let source: PlayerSource

    @State private var player = AVPlayer(playerItem: nil)
    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var captionLoadTask: Task<Void, Never>?
    @State private var aspectRatioLoadTask: Task<Void, Never>?
    @State private var timeObserverToken: Any?
    @State private var loadError: String?
    @State private var videoAspectRatio = defaultAspectRatio

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

                        if let text = captionStore.activeCaptionText {
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
            player.play()
            showControlsTemporarily()
        }
        .onDisappear {
            controlsHideTask?.cancel()
            controlsHideTask = nil
            aspectRatioLoadTask?.cancel()
            aspectRatioLoadTask = nil
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

    private func load(_ source: PlayerSource) async {
        loadError = nil
        cancelCaptionLoad()
        captionStore.clear()
        installCaptionTimeObserver()

        do {
            try Task.checkCancellation()

            switch source {
            case .directURL(let url):
                replaceCurrentItem(AVPlayerItem(url: url))
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

        let stream = try StreamExtractor.resolve(from: response)
        try Task.checkCancellation()
        replaceCurrentItem(makeYouTubePlayerItem(stream: stream))

        if let track = response.captionTracks.first {
            startCaptionLoad(
                track,
                using: YouTubeCaptionService.shared,
                initialPlaybackTime: player.currentTime().seconds
            )
        } else {
            captionStore.clear()
        }
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
        aspectRatioLoadTask?.cancel()
        videoAspectRatio = Self.defaultAspectRatio
        player.replaceCurrentItem(with: item)

        aspectRatioLoadTask = Task { @MainActor in
            await loadAspectRatio(from: item)
        }
    }

    private func loadAspectRatio(from item: AVPlayerItem) async {
        for _ in 0..<40 {
            guard !Task.isCancelled else {
                return
            }

            if let aspectRatio = Self.aspectRatio(from: item.presentationSize) {
                videoAspectRatio = aspectRatio
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func makeYouTubePlayerItem(stream: Stream) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: stream.url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": Self.youtubePlaybackUserAgent,
                ],
            ]
        )

        return AVPlayerItem(asset: asset)
    }

    private static let youtubePlaybackUserAgent = InnertubeContextProvider.androidVRUserAgent
    private static let defaultAspectRatio = 16.0 / 9.0

    private static func aspectRatio(from presentationSize: CGSize) -> CGFloat? {
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
