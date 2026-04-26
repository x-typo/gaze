import SwiftUI

struct HomeView: View {
    @State private var searchQuery = ""
    @State private var submittedSearchQuery: String?
    @State private var isShowingSearchResults = false
    @State private var isURLInputExpanded = false
    @State private var videoInput = ""
    @State private var submittedVideoID: String?
    @State private var isShowingPlayer = false
    @State private var validationMessage: String?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                searchBar

                Button(action: submitSearch) {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedSearchQuery.isEmpty)
            }

            DisclosureGroup(isExpanded: $isURLInputExpanded) {
                urlHarness
                    .padding(.top, 12)
            } label: {
                Label("Open URL", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 460, maxHeight: .infinity)
        .background(Theme.background)
        .navigationDestination(isPresented: $isShowingSearchResults) {
            if let submittedSearchQuery {
                SearchResultsView(query: submittedSearchQuery)
            }
        }
        .navigationDestination(isPresented: $isShowingPlayer) {
            if let submittedVideoID {
                PlayerScreen(videoID: submittedVideoID)
            } else {
                PlayerScreen()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search YouTube", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focusedField, equals: .search)
                .onSubmit(submitSearch)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var urlHarness: some View {
        VStack(spacing: 12) {
            TextField("YouTube URL or video ID", text: $videoInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .url)
                .onSubmit(openVideo)

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: openVideo) {
                Label("Open Video", systemImage: "play.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                submittedVideoID = nil
                focusedField = nil
                isShowingPlayer = true
            } label: {
                Label("Open Local Player", systemImage: "play.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitSearch() {
        let query = trimmedSearchQuery
        guard !query.isEmpty else {
            return
        }

        submittedSearchQuery = query
        focusedField = nil
        isShowingSearchResults = true
    }

    private func openVideo() {
        guard let videoID = Self.extractVideoID(from: videoInput) else {
            validationMessage = "Enter a valid YouTube URL or video ID."
            return
        }

        validationMessage = nil
        submittedVideoID = videoID
        focusedField = nil
        isShowingPlayer = true
    }

    private static func extractVideoID(from input: String) -> String? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        if isValidVideoID(trimmedInput) {
            return trimmedInput
        }

        let normalizedInput = trimmedInput.contains("://")
            ? trimmedInput
            : "https://\(trimmedInput)"
        guard let components = URLComponents(string: normalizedInput),
              let host = components.host?.lowercased() else {
            return nil
        }

        if host == "youtu.be",
           let videoID = pathComponents(from: components.path).first,
           isValidVideoID(videoID) {
            return videoID
        }

        guard host == "youtube.com"
            || host == "www.youtube.com"
            || host == "m.youtube.com"
            || host == "music.youtube.com"
            || host == "youtube-nocookie.com"
            || host == "www.youtube-nocookie.com" else {
            return nil
        }

        if let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidVideoID(videoID) {
            return videoID
        }

        let pathComponents = pathComponents(from: components.path)
        guard pathComponents.count >= 2,
              ["embed", "live", "shorts", "v"].contains(pathComponents[0]),
              isValidVideoID(pathComponents[1]) else {
            return nil
        }

        return pathComponents[1]
    }

    private static func pathComponents(from path: String) -> [String] {
        path
            .split(separator: "/")
            .map(String.init)
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        let allowedScalars = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "_-"))
        return value.count == 11
            && value.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
    }

    private enum FocusedField {
        case search
        case url
    }
}
