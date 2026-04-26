import SwiftUI

struct PaginationFooterView: View {
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        Group {
            if let errorMessage, !isLoading {
                VStack(spacing: 8) {
                    Text("Load More Failed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Button("Retry", action: retry)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }
}
