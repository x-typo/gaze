import SwiftUI

struct PlaylistsView: View {
    var body: some View {
        ContentUnavailableView(
            "Playlists",
            systemImage: "list.bullet",
            description: Text("Playlist management will be restored here.")
        )
    }
}
