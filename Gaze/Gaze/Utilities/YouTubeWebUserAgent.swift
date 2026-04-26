import Foundation

nonisolated enum YouTubeWebUserAgent {
    static let mobileSafari = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/18.0 Mobile/15E148 Safari/604.1",
    ].joined(separator: " ")

    static let desktopSafari = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.0 Safari/605.1.15",
    ].joined(separator: " ")
}
