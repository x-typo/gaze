import Foundation

protocol CaptionCueFetching: Sendable {
    func fetchCues(for track: CaptionTrack) async throws -> [CaptionCue]
}

struct LocalCaptionCueService: CaptionCueFetching {
    let vttText: String

    func fetchCues(for track: CaptionTrack) async throws -> [CaptionCue] {
        try VTTParser.parse(vttText)
    }
}

actor YouTubeCaptionService: CaptionCueFetching {
    static let shared = YouTubeCaptionService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCues(for track: CaptionTrack) async throws -> [CaptionCue] {
        let vttText = try await fetchVTT(for: track)
        return try VTTParser.parse(vttText)
    }

    func fetchVTT(for track: CaptionTrack) async throws -> String {
        let url = try vttURL(for: track.baseURL)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeCaptionServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw YouTubeCaptionServiceError.httpStatus(httpResponse.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw YouTubeCaptionServiceError.invalidUTF8
        }

        return text
    }

    private func vttURL(for baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw YouTubeCaptionServiceError.invalidTrackURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "fmt" }
        queryItems.append(URLQueryItem(name: "fmt", value: "vtt"))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw YouTubeCaptionServiceError.invalidTrackURL
        }

        return url
    }
}

enum YouTubeCaptionServiceError: Error, LocalizedError {
    case invalidTrackURL
    case invalidResponse
    case httpStatus(Int)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidTrackURL:
            "Caption track URL is invalid."
        case .invalidResponse:
            "Caption request did not return an HTTP response."
        case .httpStatus(let statusCode):
            "Caption request failed with HTTP \(statusCode)."
        case .invalidUTF8:
            "Caption response was not valid UTF-8 text."
        }
    }
}
