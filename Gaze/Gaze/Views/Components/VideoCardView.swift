import SwiftUI

struct VideoCardView: View {
    let video: Video

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let channelTitle = video.channelTitle {
                    Text(channelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: video.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .overlay {
                            Image(systemName: "play.rectangle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    Rectangle()
                        .fill(.white.opacity(0.08))
                }
            }
            .frame(width: 132, height: 74)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let durationText = video.durationText {
                Text(durationText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
        }
        .frame(width: 132, height: 74)
    }

    private var metadataText: String {
        [
            video.viewCountText,
            video.publishedText,
        ]
        .compactMap { value in
            value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty
        }
        .joined(separator: " - ")
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
