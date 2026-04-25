import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "Home",
                systemImage: "magnifyingglass",
                description: Text("Search will be restored after the player layout is right.")
            )

            NavigationLink {
                PlayerScreen()
            } label: {
                Label("Open Player", systemImage: "play.rectangle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}
