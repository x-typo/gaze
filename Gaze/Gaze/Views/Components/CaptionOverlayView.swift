import SwiftUI

struct CaptionOverlayView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .lineLimit(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.50))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(text)
    }
}
