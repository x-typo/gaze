import AVFoundation
import SwiftUI

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.backgroundColor = UIColor.black.cgColor
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

struct CenteredVideoPlayerView<Overlay: View>: View {
    let player: AVPlayer
    let aspectRatio: CGFloat

    private let overlay: () -> Overlay

    init(
        player: AVPlayer,
        aspectRatio: CGFloat = 16.0 / 9.0,
        @ViewBuilder overlay: @escaping () -> Overlay = { EmptyView() }
    ) {
        self.player = player
        self.aspectRatio = aspectRatio
        self.overlay = overlay
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = videoRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color.black
                    .ignoresSafeArea()

                ZStack {
                    VideoPlayerView(player: player)

                    overlay()
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func videoRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else {
            return .zero
        }

        let widthFromHeight = size.height * aspectRatio
        let finalSize: CGSize

        if widthFromHeight <= size.width {
            finalSize = CGSize(width: widthFromHeight, height: size.height)
        } else {
            finalSize = CGSize(width: size.width, height: size.width / aspectRatio)
        }

        return CGRect(
            x: (size.width - finalSize.width) / 2,
            y: (size.height - finalSize.height) / 2,
            width: finalSize.width,
            height: finalSize.height
        )
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
