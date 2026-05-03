import SwiftUI

struct PaginationFooterView: View {
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        Group {
            if errorMessage != nil, !isLoading {
                failureView()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    private func failureView() -> some View {
        let presentation = RecoveryPresentation.make(for: .paginationFailure)

        return VStack(spacing: 8) {
            Text(presentation.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            Text(presentation.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button(presentation.primaryActionTitle ?? "Retry", action: retry)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .padding(.top, 2)
        }
    }
}
