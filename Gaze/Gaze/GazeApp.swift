import SwiftUI
import AVFoundation

@main
struct GazeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var selectedTab = AppTab.home
    @State private var youtubeSession = YouTubeSession()
    @State private var playlistsStore = PlaylistsStore()
    @State private var searchStore = SearchStore()
    @State private var playbackStore = PlaybackStore()
    @State private var captionStore = CaptionStore()

    init() {
        configureRuntime()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(selectedTab: $selectedTab)
                .environment(youtubeSession)
                .environment(playlistsStore)
                .environment(searchStore)
                .environment(playbackStore)
                .environment(captionStore)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }

    private func configureRuntime() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        URLCache.shared = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
    }
}
