import SwiftUI

struct SettingsView: View {
    @Environment(YouTubeSession.self) private var youtubeSession
    @State private var isShowingLogin = false
    @State private var isShowingPlaylistWebPage = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label("YouTube", systemImage: "play.rectangle")

                    Spacer()

                    Text(youtubeSession.isSignedIn ? "Signed In" : "Signed Out")
                        .foregroundStyle(.secondary)
                }

                if youtubeSession.isSignedIn {
                    Button {
                        Task {
                            await youtubeSession.verifyAuthenticatedSession()
                        }
                    } label: {
                        HStack {
                            Label(
                                youtubeSession.isVerifyingSession ? "Checking Session" : "Check Session",
                                systemImage: "checkmark.shield"
                            )

                            Spacer()

                            if youtubeSession.isVerifyingSession {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(youtubeSession.isVerifyingSession)

                    Button {
                        Task {
                            await youtubeSession.inspectAuthCookies()
                        }
                    } label: {
                        Label("Check Auth Cookies", systemImage: "text.magnifyingglass")
                    }

                    Button {
                        isShowingPlaylistWebPage = true
                    } label: {
                        Label("Open YouTube Playlists Page", systemImage: "safari")
                    }

                    if let statusMessage = youtubeSession.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        Task {
                            await youtubeSession.signOut()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        isShowingLogin = true
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            youtubeSession.restoreSession()
        }
        .sheet(isPresented: $isShowingLogin) {
            NavigationStack {
                LoginView()
            }
        }
        .sheet(isPresented: $isShowingPlaylistWebPage) {
            NavigationStack {
                YouTubeWebPageView(
                    title: "YouTube Playlists",
                    url: YouTubeWebPageView.playlistsURL
                )
            }
        }
    }
}
