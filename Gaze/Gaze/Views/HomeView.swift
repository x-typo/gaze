import SwiftUI

struct HomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Home",
            systemImage: "magnifyingglass",
            description: Text("Search and playback will be restored here.")
        )
    }
}
