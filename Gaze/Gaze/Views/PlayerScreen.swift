import AVFoundation
import SwiftUI

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?

    init(url: URL = demoStreamURL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            CenteredVideoPlayerView(
                player: player,
                aspectRatio: 16.0 / 9.0
            ) {
                ZStack {
                    VStack(spacing: 0) {
                        Spacer()

                        CaptionOverlayView(text: "Big Buck Bunny finds a quiet place.")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }
                    .padding(12)

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
        .onAppear {
            player.play()
            isPlaying = true
            showControlsTemporarily()
        }
        .onDisappear {
            controlsHideTask?.cancel()
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

        isPlaying.toggle()
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
        }
    }
}

private let demoStreamURL = URL(
    string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
)!
