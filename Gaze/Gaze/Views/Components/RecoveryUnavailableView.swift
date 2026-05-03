import SwiftUI

struct RecoveryUnavailableView<Actions: View>: View {
    private let presentation: RecoveryPresentation
    private let actions: Actions

    init(
        _ presentation: RecoveryPresentation,
        @ViewBuilder actions: () -> Actions
    ) {
        self.presentation = presentation
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.systemImage)
        } description: {
            Text(presentation.message)
        } actions: {
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension RecoveryUnavailableView where Actions == EmptyView {
    init(_ presentation: RecoveryPresentation) {
        self.presentation = presentation
        actions = EmptyView()
    }
}
