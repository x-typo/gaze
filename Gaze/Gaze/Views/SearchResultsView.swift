import SwiftUI

struct SearchResultsView: View {
    @Environment(SearchStore.self) private var searchStore

    let query: String

    @State private var searchText: String
    @FocusState private var isSearchFocused: Bool

    init(query: String) {
        self.query = query
        _searchText = State(initialValue: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

            content
        }
        .background(Theme.background)
        .navigationTitle(searchStore.query.isEmpty ? "Search" : searchStore.query)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            searchText = query
            await searchStore.searchVideos(query: query)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search YouTube", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit(submitSearch)

            Button(action: submitSearch) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .disabled(trimmedSearchText.isEmpty)
            .accessibilityLabel("Search")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if searchStore.isLoading && searchStore.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = searchStore.errorMessage,
                  searchStore.results.isEmpty {
            ContentUnavailableView(
                "Search Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchStore.hasSearched && searchStore.results.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchStore.results) { video in
                    NavigationLink {
                        PlayerScreen(videoID: video.id)
                    } label: {
                        VideoCardView(video: video)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(.white.opacity(0.08))
                }

                searchContinuationView
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            await searchStore.searchVideos(query: activeQuery)
        }
    }

    @ViewBuilder
    private var searchContinuationView: some View {
        if searchStore.continuation != nil {
            PaginationFooterView(
                isLoading: searchStore.isLoadingMore,
                errorMessage: searchStore.errorMessage
            ) {
                Task {
                    await searchStore.loadMore()
                }
            }
                .task(id: searchStore.continuation) {
                    guard searchStore.errorMessage == nil else {
                        return
                    }

                    await searchStore.loadMore()
                }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeQuery: String {
        searchStore.query.isEmpty ? query : searchStore.query
    }

    private func submitSearch() {
        let submittedQuery = trimmedSearchText
        guard !submittedQuery.isEmpty else {
            return
        }

        isSearchFocused = false

        Task {
            await searchStore.searchVideos(query: submittedQuery)
        }
    }
}
