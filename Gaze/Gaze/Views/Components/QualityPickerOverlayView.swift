import SwiftUI

struct QualityPickerOverlayView: View {
    let options: [PlayableQualityOption]
    let selectedID: String
    let onSelect: (PlayableQualityOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Text("Quality")
                        .font(.headline.weight(.semibold))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()
                    .overlay(.white.opacity(0.22))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "checkmark")
                                        .font(.title3.weight(.semibold))
                                        .opacity(option.id == selectedID ? 1 : 0)
                                        .frame(width: 26)

                                    Text(option.label)
                                        .font(.title3)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)

                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.white)
                                .frame(height: 56)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 320)
            .frame(maxHeight: 420)
            .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 22)
            .padding(.trailing, 18)
        }
    }
}
