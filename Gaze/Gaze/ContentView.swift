//
//  ContentView.swift
//  Gaze
//
//  Task 2+7 PREVIEW — pseudo-fullscreen AVPlayer + custom in-frame caption overlay.
//  Captions source: VTT auto-captions pulled via yt-dlp from the test video, cleaned
//  (duplicate bridge cues collapsed, inline timing tags stripped), embedded as literals.
//  Proves the "YouTube-style captions inside the video frame" concept before Tasks 3-6.
//

import SwiftUI
import AVKit
import AVFoundation

struct Cue {
    let start: Double
    let end: Double
    let text: String
}

private let cues: [Cue] = [
    Cue(start: 0.080, end: 1.839, text: "Most people are stuck on the wrong side"),
    Cue(start: 1.839, end: 4.400, text: "of using AI without realizing it because"),
    Cue(start: 4.400, end: 7.200, text: "AI model change new features every week."),
    Cue(start: 7.200, end: 10.000, text: "So people try everything and eventually"),
    Cue(start: 10.000, end: 11.759, text: "get overwhelmed. I have been there"),
    Cue(start: 11.759, end: 14.240, text: "before using AI but never felt like I"),
    Cue(start: 14.240, end: 16.320, text: "was truly getting the most out of it. So"),
    Cue(start: 16.320, end: 18.240, text: "in this video I'll share the path to get"),
    Cue(start: 18.240, end: 20.480, text: "started with AI and we transform"),
    Cue(start: 20.480, end: 24.160, text: "completely how I use it. Let's go."),
    Cue(start: 24.160, end: 25.920, text: "The first part is learning how to"),
    Cue(start: 25.920, end: 27.920, text: "communicate with AI. And communication"),
    Cue(start: 27.920, end: 30.480, text: "all starts with effective AI prompting."),
    Cue(start: 30.480, end: 32.719, text: "After spending two years prompting AI"),
    Cue(start: 32.719, end: 35.040, text: "every day, the most critical components"),
    Cue(start: 35.040, end: 36.640, text: "for an effective prompts [music] are"),
    Cue(start: 36.640, end: 38.719, text: "really these three. Clear task. The"),
    Cue(start: 38.719, end: 41.360, text: "what. What exactly do you want? Is it a"),
    Cue(start: 41.360, end: 43.840, text: "proposal, a landing page, a social"),
    Cue(start: 43.840, end: 46.559, text: "visual? If you're confused, AI will get"),
    Cue(start: 46.559, end: 49.680, text: "confused too. Relevant context. The why."),
    Cue(start: 49.680, end: 51.600, text: "What are the background details? AI"),
    Cue(start: 51.600, end: 53.360, text: "needs to understand your situation."),
    Cue(start: 53.360, end: 55.920, text: "Instead of bring down everything to AI,"),
    Cue(start: 55.920, end: 58.239, text: "think about why this context matters."),
    Cue(start: 58.239, end: 60.640, text: "Output format, the how, how a good"),
    Cue(start: 60.640, end: 62.879, text: "output should look like for your task, a"),
    Cue(start: 62.879, end: 65.519, text: "table, a work document, file, bullet"),
    Cue(start: 65.519, end: 67.840, text: "points. So like this example about a"),
    Cue(start: 67.840, end: 69.760, text: "performance review conversation, chart"),
    Cue(start: 69.760, end: 72.080, text: "GPT is still able to give us a decent"),
    Cue(start: 72.080, end: 74.240, text: "response. But if we intentionally"),
    Cue(start: 74.240, end: 76.400, text: "mention the clear task, the welf"),
    Cue(start: 76.400, end: 78.720, text: "context, the output format, you will see"),
    Cue(start: 78.720, end: 81.200, text: "the response improve dramatically. Bonus"),
    Cue(start: 81.200, end: 83.759, text: "tip is you can always let AI to ask you"),
    Cue(start: 83.759, end: 86.400, text: "question to uncover what are the context"),
    Cue(start: 86.400, end: 88.240, text: "that you should give in order for it to"),
    Cue(start: 88.240, end: 89.600, text: "do its [music] job. You can also add"),
    Cue(start: 89.600, end: 92.159, text: "enhancement prime elements like persona,"),
    Cue(start: 92.159, end: 95.040, text: "examples, constraints for more precision"),
    Cue(start: 95.040, end: 97.360, text: "control. But the core three elements I"),
    Cue(start: 97.360, end: 99.840, text: "mentioned are all you need for 80% of"),
    Cue(start: 99.840, end: 101.920, text: "task. Besides these core components,"),
    Cue(start: 101.920, end: 103.840, text: "here are four more techniques which are"),
    Cue(start: 103.840, end: 105.920, text: "my favorite and they apply to all sorts"),
    Cue(start: 105.920, end: 107.520, text: "of tasks. Technique number one, field"),
    Cue(start: 107.520, end: 110.320, text: "shop prompting giving examples. So when"),
    Cue(start: 110.320, end: 112.240, text: "I asked Gemini to build a landing page"),
    Cue(start: 112.240, end: 114.479, text: "with just a copy, it creates something"),
    Cue(start: 114.479, end: 117.600, text: "decent but looks standard. But what if I"),
    Cue(start: 117.600, end: 120.000, text: "give it two style screenshot examples?"),
]

struct ContentView: View {
    @State private var player = AVPlayer()
    @State private var currentCue: Cue?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(player: player)
                .ignoresSafeArea(.all)

            // Task 7 preview — caption pinned to video frame bottom, not screen bottom.
            // Aspect-ratio container matches the video's actual display rect (resizeAspect),
            // so in portrait the caption sits at the video's bottom edge (not in the letterbox),
            // and in landscape it sits at the video's bottom filling the frame.
            VStack {
                Spacer()
                if let cue = currentCue {
                    Text(cue.text)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .allowsHitTesting(false)

            // Tiny build tag so we know this version is running
            VStack {
                HStack {
                    Text("GAZE TEST v3 — captions")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(.black.opacity(0.6))
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 50)
            .padding(.leading, 12)
            .allowsHitTesting(false)
        }
        .onAppear { start() }
    }

    private func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let urlString = "https://rr1---sn-o097znzk.googlevideo.com/videoplayback?expire=1776751112&ei=qL3maZnmFIn92_gPyfzhwA8&ip=38.70.245.19&id=o-APWyp8oeKer45yB0rVP8Ts4jUKJUJ2oZAB0eRsdCnVBq&itag=18&source=youtube&requiressl=yes&xpc=EgVo2aDSNQ%3D%3D&cps=295&met=1776729512%2C&mh=OX&mm=31%2C29&mn=sn-o097znzk%2Csn-najern7r&ms=au%2Crdu&mv=m&mvi=1&pl=22&rms=au%2Cau&initcwndbps=3441250&bui=AUUZDGK7u1f6AaZantnTVHgh0R-8j5KaihbEQWjVvuPaG8iUbMsMTUDugvyYHsXy1jJEgVsPmrSTH26s&spc=jlWavcUB8dYb4zUvDm36QKby5Cog9lMpX1UfguWBYFGB_2o6JcqS&vprv=1&svpuc=1&mime=video%2Fmp4&rqh=1&gir=yes&clen=48837318&ratebypass=yes&dur=1075.989&lmt=1767132147776253&mt=1776729193&fvip=1&fexp=51565116%2C51565682&c=ANDROID_VR&txp=5538534&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cxpc%2Cbui%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Crqh%2Cgir%2Cclen%2Cratebypass%2Cdur%2Clmt&sig=AHEqNM4wRQIgMAnqg4X0tJS1Cq3EkTHiWSDicO2W39E52Qt6sBO2K-cCIQDC7RN40YdQI8VMFrzM3QXN-HByGtY-WKqUagcW6y3J7A%3D%3D&lsparams=cps%2Cmet%2Cmh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Crms%2Cinitcwndbps&lsig=APaTxxMwRQIhAKj7YUcOnYMg74uf8KqcDjHU4JtIWqxcp4a0Vfr2T43wAiAgPso-ppiwD2tBGdJgSrL08gLd7KOoXXUGaOx-0ew8Hg%3D%3D"

        guard let url = URL(string: urlString) else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()

        // Periodic time observer — updates currentCue via binary search
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            currentCue = findCue(at: seconds)
        }
    }

    private func findCue(at seconds: Double) -> Cue? {
        var low = 0
        var high = cues.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            if seconds < cue.start {
                high = mid - 1
            } else if seconds >= cue.end {
                low = mid + 1
            } else {
                return cue
            }
        }
        return nil
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.backgroundColor = UIColor.black.cgColor
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
