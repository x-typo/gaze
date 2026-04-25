import SwiftUI

enum AppTab: Hashable {
    case home
    case playlists
    case settings
}

struct ContentView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            SwiftUI.Tab("Home", systemImage: "magnifyingglass", value: AppTab.home) {
                TabNavigationWrapper {
                    HomeView()
                }
            }

            SwiftUI.Tab("Playlists", systemImage: "list.bullet", value: AppTab.playlists) {
                TabNavigationWrapper {
                    PlaylistsView()
                }
            }

            SwiftUI.Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                TabNavigationWrapper {
                    SettingsView()
                }
            }
        }
        .background(Theme.background)
    }
}
