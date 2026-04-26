import Foundation

actor YouTubeClient {
    static let shared = YouTubeClient()

    private let session: URLSession
    private let contextProvider: InnertubeContextProvider
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        session: URLSession = .shared,
        contextProvider: InnertubeContextProvider = .shared
    ) {
        self.session = session
        self.contextProvider = contextProvider
    }

    func player(videoID: String) async throws -> PlayerResponse {
        do {
            let playerResponse = try await androidVRPlayer(videoID: videoID)
            if playerResponse.hasPlayableStream {
                return playerResponse
            }

            if let webResponse = try? await innertubePlayer(videoID: videoID),
               webResponse.hasPlayableStream {
                return webResponse
            }

            if let watchResponse = try? await watchPagePlayer(videoID: videoID),
               watchResponse.hasPlayableStream {
                return watchResponse
            }

            return playerResponse
        } catch {
            do {
                return try await watchPagePlayer(videoID: videoID)
            } catch {
                throw error
            }
        }
    }

    func resolveStream(videoID: String) async throws -> Stream {
        let response = try await player(videoID: videoID)
        try response.validatePlayable()
        return try StreamExtractor.resolve(from: response)
    }

    private func androidVRPlayer(videoID: String) async throws -> PlayerResponse {
        let bootstrap = try await contextProvider.bootstrap()
        let context = try await contextProvider.androidVRContext()
        let payload = PlayerRequestPayload(
            context: context,
            videoID: videoID
        )

        var headers = [
            "User-Agent": InnertubeContextProvider.androidVRUserAgent,
            "Origin": "https://www.youtube.com",
            "X-YouTube-Client-Name": "28",
            "X-YouTube-Client-Version": InnertubeContextProvider.androidVRClientVersion,
        ]

        if let visitorData = bootstrap.visitorData {
            headers["X-Goog-Visitor-Id"] = visitorData
        }

        return try await execute(
            endpoint: .player,
            payload: payload,
            responseType: PlayerResponse.self,
            headers: headers
        )
    }

    private func innertubePlayer(videoID: String) async throws -> PlayerResponse {
        let context = try await contextProvider.context()
        let payload = PlayerRequestPayload(
            context: context,
            videoID: videoID
        )

        return try await execute(
            endpoint: .player,
            payload: payload,
            responseType: PlayerResponse.self,
            headers: [:]
        )
    }

    private func watchPagePlayer(videoID: String) async throws -> PlayerResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [
            URLQueryItem(name: "v", value: videoID),
        ]

        guard let url = components.url else {
            throw YouTubeError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw YouTubeError.http(httpResponse.statusCode, nil)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw YouTubeError.invalidResponse
        }

        let playerResponseJSON = try Self.extractJSONObject(
            assignedTo: "ytInitialPlayerResponse",
            from: html
        )
        guard let playerResponseData = playerResponseJSON.data(using: .utf8) else {
            throw YouTubeError.invalidResponse
        }

        do {
            return try decoder.decode(PlayerResponse.self, from: playerResponseData)
        } catch {
            throw YouTubeError.decoding(error)
        }
    }

    private func execute<Payload: Encodable, Response: Decodable>(
        endpoint: InnertubeEndpoint,
        payload: Payload,
        responseType: Response.Type,
        headers: [String: String]
    ) async throws -> Response {
        let bootstrap = try await contextProvider.bootstrap()
        let url = try endpoint.url(apiKey: bootstrap.apiKey)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        headers.forEach { field, value in
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw YouTubeError.http(httpResponse.statusCode, body)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw YouTubeError.decoding(error)
        }
    }

    private nonisolated static func extractJSONObject(
        assignedTo variableName: String,
        from html: String
    ) throws -> String {
        let assignmentPattern = "\(variableName) = "
        guard let assignmentRange = html.range(of: assignmentPattern) else {
            throw YouTubeError.missingPlayerResponse
        }

        let objectStart = assignmentRange.upperBound
        var cursor = objectStart
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while cursor < html.endIndex {
            let character = html[cursor]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1

                if depth == 0 {
                    let objectEnd = html.index(after: cursor)
                    return String(html[objectStart..<objectEnd])
                }
            }

            cursor = html.index(after: cursor)
        }

        throw YouTubeError.malformedPlayerResponse
    }

    nonisolated private static let userAgent = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.0 Safari/605.1.15",
    ].joined(separator: " ")
}

nonisolated enum InnertubeEndpoint: String, Sendable {
    case browse
    case search
    case player
    case next
    case accountsList = "account/accounts_list"

    func url(apiKey: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/youtubei/v1/\(rawValue)"
        components.queryItems = [
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw YouTubeError.invalidEndpoint
        }

        return url
    }
}

nonisolated enum YouTubeError: Error, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case http(Int, String?)
    case decoding(Error)
    case playabilityBlocked(String)
    case streamUnsupported(String)
    case missingPlayerResponse
    case malformedPlayerResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "YouTube endpoint URL is invalid."
        case .invalidResponse:
            "YouTube request did not return an HTTP response."
        case .http(let statusCode, let body):
            if let body, !body.isEmpty {
                "YouTube request failed with HTTP \(statusCode): \(body)"
            } else {
                "YouTube request failed with HTTP \(statusCode)."
            }
        case .decoding(let error):
            "YouTube response decoding failed: \(error.localizedDescription)"
        case .playabilityBlocked(let reason):
            "YouTube blocked playback: \(reason)"
        case .streamUnsupported(let reason):
            "No supported YouTube stream was found: \(reason)"
        case .missingPlayerResponse:
            "YouTube watch page did not include an initial player response."
        case .malformedPlayerResponse:
            "YouTube watch page player response could not be parsed."
        }
    }
}

private extension PlayerResponse {
    nonisolated var hasPlayableStream: Bool {
        playabilityStatus?.status == "OK" && StreamExtractor.canResolve(from: self)
    }

    nonisolated func validatePlayable() throws {
        guard let status = playabilityStatus?.status else {
            throw YouTubeError.playabilityBlocked("missing playability status")
        }

        switch status {
        case "OK":
            return
        case "LOGIN_REQUIRED":
            throw YouTubeError.playabilityBlocked("sign in required")
        case "AGE_VERIFICATION_REQUIRED":
            throw YouTubeError.playabilityBlocked("age-verified account needed")
        case "CONTENT_CHECK_REQUIRED":
            throw YouTubeError.playabilityBlocked("content check required")
        case "UNPLAYABLE", "ERROR":
            throw YouTubeError.playabilityBlocked(playabilityStatus?.reason ?? "unavailable")
        default:
            throw YouTubeError.playabilityBlocked(playabilityStatus?.reason ?? status)
        }
    }
}
