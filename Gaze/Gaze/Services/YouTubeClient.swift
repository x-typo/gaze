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
        var playableFallback: PlayerResponse?

        if let iOSResponse = try? await iOSPlayer(videoID: videoID),
           iOSResponse.hasPlayableStream {
            if iOSResponse.hasHLSStream {
                return iOSResponse
            }

            playableFallback = iOSResponse
        }

        do {
            let playerResponse = try await androidVRPlayer(videoID: videoID)
            if playerResponse.hasHLSStream {
                return playerResponse
            }

            if playerResponse.hasPlayableStream {
                playableFallback = playableFallback ?? playerResponse
            }

            if let webResponse = try? await innertubePlayer(videoID: videoID),
               webResponse.hasPlayableStream {
                if webResponse.hasHLSStream {
                    return webResponse
                }

                playableFallback = playableFallback ?? webResponse
            }

            if let watchResponse = try? await watchPagePlayer(videoID: videoID),
               watchResponse.hasPlayableStream {
                if watchResponse.hasHLSStream {
                    return watchResponse
                }

                playableFallback = playableFallback ?? watchResponse
            }

            return playableFallback ?? playerResponse
        } catch {
            if let playableFallback {
                return playableFallback
            }

            let primaryError = error
            do {
                return try await watchPagePlayer(videoID: videoID)
            } catch {
                throw YouTubeError.fallbackFailed(primary: primaryError, fallback: error)
            }
        }
    }

    func resolveStream(videoID: String) async throws -> Stream {
        let response = try await player(videoID: videoID)
        try response.validatePlayable()
        return try StreamExtractor.resolve(from: response)
    }

    func searchVideos(query: String, continuation: String? = nil) async throws -> SearchPage {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return SearchPage(videos: [], continuation: nil)
        }

        let context = try await contextProvider.context()
        let payload = SearchRequestPayload(
            context: context,
            query: continuation == nil ? trimmedQuery : nil,
            continuation: continuation
        )

        let response = try await execute(
            endpoint: .search,
            payload: payload,
            responseType: SearchResponse.self,
            headers: [:]
        )

        return response.searchPage
    }

    func authenticatedSessionProbe(
        sapisid: String,
        cookieHeader: String
    ) async throws -> AuthProbeResult {
        let context = try await contextProvider.context()
        let payload = AccountsListRequestPayload(context: context)
        let data = try await executeData(
            endpoint: .accountsList,
            payload: payload,
            headers: authenticatedHeaders(
                sapisid: sapisid,
                cookieHeader: cookieHeader
            )
        )

        return AuthProbeResult(responseByteCount: data.count)
    }

    func nativePlaylistPageProbe(authContext: YouTubeAuthContext) async throws -> NativePageProbeResult {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/feed/playlists"
        components.queryItems = [
            URLQueryItem(name: "persist_app", value: "1"),
            URLQueryItem(name: "app", value: "desktop"),
        ]

        guard let url = components.url else {
            throw YouTubeError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(authContext.nativePageCookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw YouTubeError.http(httpResponse.statusCode, body)
        }

        let finalHost = httpResponse.url?.host?.lowercased()
        let finalPath = httpResponse.url?.path

        return NativePageProbeResult(
            responseByteCount: data.count,
            finalHost: finalHost,
            finalPath: finalPath,
            wasRedirectedToSignIn: Self.isSignInRedirect(host: finalHost, path: finalPath)
        )
    }

    func playlists(
        authContext: YouTubeAuthContext,
        continuation: String? = nil
    ) async throws -> PlaylistPage {
        let context = try await contextProvider.context()
        let payload = BrowseRequestPayload(
            context: context,
            browseID: continuation == nil ? "FEplaylist_aggregation" : nil,
            continuation: continuation
        )
        let data = try await executeData(
            endpoint: .browse,
            payload: payload,
            headers: authenticatedHeaders(authContext: authContext)
        )

        return try PlaylistResponseParser.playlistPage(from: data)
    }

    func playlistVideos(
        authContext: YouTubeAuthContext,
        continuation: String
    ) async throws -> PlaylistVideoPage {
        let context = try await contextProvider.context()
        let payload = BrowseRequestPayload(
            context: context,
            continuation: continuation
        )
        let data = try await executeData(
            endpoint: .browse,
            payload: payload,
            headers: authenticatedHeaders(authContext: authContext)
        )

        return try VideoResponseParser.playlistVideoPage(from: data)
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
        ).withPlaybackUserAgent(InnertubeContextProvider.androidVRUserAgent)
    }

    private func iOSPlayer(videoID: String) async throws -> PlayerResponse {
        let bootstrap = try await contextProvider.bootstrap()
        let context = try await contextProvider.iOSContext()
        let payload = PlayerRequestPayload(
            context: context,
            videoID: videoID
        )

        var headers = [
            "User-Agent": InnertubeContextProvider.iOSUserAgent,
            "Origin": "https://www.youtube.com",
            "X-YouTube-Client-Name": "5",
            "X-YouTube-Client-Version": InnertubeContextProvider.iOSClientVersion,
        ]

        if let visitorData = bootstrap.visitorData {
            headers["X-Goog-Visitor-Id"] = visitorData
        }

        return try await execute(
            endpoint: .player,
            payload: payload,
            responseType: PlayerResponse.self,
            headers: headers
        ).withPlaybackUserAgent(InnertubeContextProvider.iOSUserAgent)
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
        ).withPlaybackUserAgent(Self.userAgent)
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
                .withPlaybackUserAgent(Self.userAgent)
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
        let data = try await executeData(
            endpoint: endpoint,
            payload: payload,
            headers: headers
        )

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw YouTubeError.decoding(error)
        }
    }

    private func executeData<Payload: Encodable>(
        endpoint: InnertubeEndpoint,
        payload: Payload,
        headers: [String: String]
    ) async throws -> Data {
        let bootstrap = try await contextProvider.bootstrap()
        let url = try endpoint.url(apiKey: bootstrap.apiKey)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(payload)
        if Self.hasManualCookieHeader(headers) {
            request.httpShouldHandleCookies = false
        }
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(bootstrap.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        if let visitorData = bootstrap.visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
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

        return data
    }

    private nonisolated static func hasManualCookieHeader(_ headers: [String: String]) -> Bool {
        headers.keys.contains { $0.caseInsensitiveCompare("Cookie") == .orderedSame }
    }

    private nonisolated static func isSignInRedirect(host: String?, path: String?) -> Bool {
        guard let host else {
            return false
        }

        return host.contains("accounts.google.com")
            || host.contains("signin")
            || path?.contains("signin") == true
    }

    private func authenticatedHeaders(
        authContext: YouTubeAuthContext
    ) -> [String: String] {
        authenticatedHeaders(
            sapisid: authContext.sapisid,
            cookieHeader: authContext.cookieHeader
        )
    }

    private func authenticatedHeaders(
        sapisid: String,
        cookieHeader: String
    ) -> [String: String] {
        [
            "Authorization": SAPISIDHash.authorizationHeader(sapisid: sapisid),
            "Cookie": cookieHeader,
            "X-Goog-AuthUser": "0",
            "X-Origin": "https://www.youtube.com",
        ]
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

nonisolated enum PlaylistResponseParser {
    static func playlistPage(from data: Data) throws -> PlaylistPage {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeError.decoding(error)
        }

        var playlists: [Playlist] = []
        var seenPlaylistIDs = Set<String>()
        collectPlaylists(from: root, into: &playlists, seenPlaylistIDs: &seenPlaylistIDs)

        return PlaylistPage(
            playlists: playlists,
            continuation: continuation(from: root)
        )
    }

    private static func collectPlaylists(
        from value: Any,
        into playlists: inout [Playlist],
        seenPlaylistIDs: inout Set<String>
    ) {
        if let dictionary = value as? [String: Any] {
            appendPlaylist(
                playlist(from: dictionary["gridPlaylistRenderer"]),
                into: &playlists,
                seenPlaylistIDs: &seenPlaylistIDs
            )
            appendPlaylist(
                playlist(from: dictionary["playlistRenderer"]),
                into: &playlists,
                seenPlaylistIDs: &seenPlaylistIDs
            )
            appendPlaylist(
                playlist(from: dictionary["lockupViewModel"]),
                into: &playlists,
                seenPlaylistIDs: &seenPlaylistIDs
            )

            for child in dictionary.values {
                collectPlaylists(
                    from: child,
                    into: &playlists,
                    seenPlaylistIDs: &seenPlaylistIDs
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectPlaylists(
                    from: child,
                    into: &playlists,
                    seenPlaylistIDs: &seenPlaylistIDs
                )
            }
        }
    }

    private static func appendPlaylist(
        _ playlist: Playlist?,
        into playlists: inout [Playlist],
        seenPlaylistIDs: inout Set<String>
    ) {
        guard let playlist, seenPlaylistIDs.insert(playlist.id).inserted else {
            return
        }

        playlists.append(playlist)
    }

    private static func playlist(from value: Any?) -> Playlist? {
        guard let renderer = value as? [String: Any],
              let playlistID = playlistID(from: renderer),
              let title = title(from: renderer) else {
            return nil
        }

        return Playlist(
            id: playlistID,
            title: title,
            videoCountText: videoCountText(from: renderer),
            thumbnailURL: thumbnailURL(from: renderer["thumbnail"])
                ?? thumbnailURL(from: renderer["thumbnailRenderer"])
                ?? thumbnailURL(from: renderer["thumbnails"])
                ?? thumbnailURL(from: renderer["contentImage"])
        )
    }

    private static func playlistID(from renderer: [String: Any]) -> String? {
        if let rendererPlaylistID = nonEmptyString(renderer["playlistId"])
            ?? nonEmptyString(renderer["playlistID"])
            ?? nonEmptyString(renderer["contentId"])
            ?? nonEmptyString(renderer["id"]) {
            return playlistID(fromBrowseID: rendererPlaylistID) ?? rendererPlaylistID
        }

        return playlistID(fromBrowseEndpointIn: renderer["navigationEndpoint"])
            ?? playlistID(fromBrowseEndpointIn: renderer["navigationEndpointData"])
            ?? playlistID(fromBrowseEndpointIn: renderer["rendererContext"])
    }

    private static func playlistID(fromBrowseEndpointIn value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let dictionary = value as? [String: Any] {
            if let browseEndpoint = dictionary["browseEndpoint"] as? [String: Any],
               let browseID = nonEmptyString(browseEndpoint["browseId"]),
               let playlistID = playlistID(fromBrowseID: browseID) {
                return playlistID
            }

            for child in dictionary.values {
                if let playlistID = playlistID(fromBrowseEndpointIn: child) {
                    return playlistID
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let playlistID = playlistID(fromBrowseEndpointIn: child) {
                    return playlistID
                }
            }
        }

        return nil
    }

    private static func playlistID(fromBrowseID browseID: String) -> String? {
        if browseID.hasPrefix("VL"), browseID.count > 2 {
            return String(browseID.dropFirst(2))
        }

        if browseID == "WL" || browseID == "LL" {
            return browseID
        }

        if browseID.hasPrefix("PL")
            || browseID.hasPrefix("UU")
            || browseID.hasPrefix("FL")
            || browseID.hasPrefix("OLAK5") {
            return browseID
        }

        return nil
    }

    private static func title(from renderer: [String: Any]) -> String? {
        text(from: renderer["title"])
            ?? text(from: renderer["headline"])
            ?? text(from: renderer["titleText"])
            ?? text(at: ["metadata", "lockupMetadataViewModel", "title"], in: renderer)
    }

    private static func videoCountText(from renderer: [String: Any]) -> String? {
        text(from: renderer["videoCountText"])
            ?? text(from: renderer["videoCountShortText"])
            ?? nonEmptyString(renderer["videoCount"])
            ?? textContainingVideoCount(in: renderer["metadata"])
    }

    private static func text(at path: [String], in dictionary: [String: Any]) -> String? {
        var value: Any? = dictionary

        for key in path {
            guard let current = value as? [String: Any] else {
                return nil
            }

            value = current[key]
        }

        return text(from: value)
    }

    private static func textContainingVideoCount(in value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let string = text(from: value),
           string.localizedCaseInsensitiveContains("video") {
            return string
        }

        if let dictionary = value as? [String: Any] {
            for child in dictionary.values {
                if let text = textContainingVideoCount(in: child) {
                    return text
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let text = textContainingVideoCount(in: child) {
                    return text
                }
            }
        }

        return nil
    }

    private static func text(from value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let string = value as? String {
            return nonEmptyText(string)
        }

        if let dictionary = value as? [String: Any] {
            if let simpleText = nonEmptyString(dictionary["simpleText"]) {
                return simpleText
            }

            if let content = nonEmptyString(dictionary["content"]) {
                return content
            }

            if let runs = dictionary["runs"] as? [Any] {
                let joinedRuns = runs
                    .compactMap { run -> String? in
                        guard let run = run as? [String: Any] else {
                            return nil
                        }

                        return run["text"] as? String
                    }
                    .joined()

                if let joinedText = nonEmptyText(joinedRuns) {
                    return joinedText
                }
            }
        }

        return nil
    }

    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let value else {
            return nil
        }

        if let dictionary = value as? [String: Any] {
            if let thumbnails = dictionary["thumbnails"] as? [Any],
               let url = thumbnailURL(fromThumbnails: thumbnails) {
                return url
            }

            if let url = url(from: dictionary["url"]) {
                return url
            }

            for child in dictionary.values {
                if let url = thumbnailURL(from: child) {
                    return url
                }
            }
        } else if let array = value as? [Any] {
            if let url = thumbnailURL(fromThumbnails: array) {
                return url
            }

            for child in array {
                if let url = thumbnailURL(from: child) {
                    return url
                }
            }
        }

        return nil
    }

    private static func thumbnailURL(fromThumbnails thumbnails: [Any]) -> URL? {
        thumbnails
            .reversed()
            .compactMap { thumbnail -> URL? in
                guard let thumbnail = thumbnail as? [String: Any] else {
                    return nil
                }

                return url(from: thumbnail["url"])
            }
            .first
    }

    private static func url(from value: Any?) -> URL? {
        guard var string = nonEmptyString(value) else {
            return nil
        }

        if string.hasPrefix("//") {
            string = "https:" + string
        } else if string.hasPrefix("/") {
            string = "https://www.youtube.com" + string
        }

        return URL(string: string)
    }

    private static func continuation(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let nextContinuationData = dictionary["nextContinuationData"] as? [String: Any],
               let continuation = nonEmptyString(nextContinuationData["continuation"]) {
                return continuation
            }

            if let continuationCommand = dictionary["continuationCommand"] as? [String: Any],
               let continuation = nonEmptyString(continuationCommand["token"])
                ?? nonEmptyString(continuationCommand["continuation"]) {
                return continuation
            }

            for child in dictionary.values {
                if let continuation = continuation(from: child) {
                    return continuation
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let continuation = continuation(from: child) {
                    return continuation
                }
            }
        }

        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        if let string = value as? String {
            return nonEmptyText(string)
        }

        if let integer = value as? Int {
            return String(integer)
        }

        return nil
    }

    private static func nonEmptyText(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum VideoResponseParser {
    static func playlistVideoPage(from data: Data) throws -> PlaylistVideoPage {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeError.decoding(error)
        }

        var videos: [Video] = []
        var seenVideoIDs = Set<String>()
        collectVideos(from: root, into: &videos, seenVideoIDs: &seenVideoIDs)

        return PlaylistVideoPage(
            videos: videos,
            continuation: continuation(from: root)
        )
    }

    private static func collectVideos(
        from value: Any,
        into videos: inout [Video],
        seenVideoIDs: inout Set<String>
    ) {
        if let dictionary = value as? [String: Any] {
            appendVideo(
                video(from: dictionary["playlistVideoRenderer"]),
                into: &videos,
                seenVideoIDs: &seenVideoIDs
            )
            appendVideo(
                video(from: dictionary["videoRenderer"]),
                into: &videos,
                seenVideoIDs: &seenVideoIDs
            )
            appendVideo(
                video(from: dictionary["lockupViewModel"]),
                into: &videos,
                seenVideoIDs: &seenVideoIDs
            )

            for child in dictionary.values {
                collectVideos(
                    from: child,
                    into: &videos,
                    seenVideoIDs: &seenVideoIDs
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideos(
                    from: child,
                    into: &videos,
                    seenVideoIDs: &seenVideoIDs
                )
            }
        }
    }

    private static func appendVideo(
        _ video: Video?,
        into videos: inout [Video],
        seenVideoIDs: inout Set<String>
    ) {
        guard let video, seenVideoIDs.insert(video.id).inserted else {
            return
        }

        videos.append(video)
    }

    private static func video(from value: Any?) -> Video? {
        guard let renderer = value as? [String: Any],
              let videoID = videoID(from: renderer),
              let title = title(from: renderer) else {
            return nil
        }

        return Video(
            id: videoID,
            title: title,
            channelTitle: channelTitle(from: renderer),
            durationText: durationText(from: renderer),
            viewCountText: viewCountText(from: renderer),
            publishedText: publishedText(from: renderer),
            thumbnailURL: thumbnailURL(from: renderer["thumbnail"])
                ?? thumbnailURL(from: renderer["thumbnailRenderer"])
                ?? thumbnailURL(from: renderer["thumbnails"])
                ?? thumbnailURL(from: renderer["contentImage"])
                ?? fallbackThumbnailURL(videoID: videoID)
        )
    }

    private static func videoID(from renderer: [String: Any]) -> String? {
        nonEmptyString(renderer["videoId"])
            ?? nonEmptyString(renderer["videoID"])
            ?? nonEmptyString(renderer["contentId"])
            ?? videoID(fromNavigationEndpointIn: renderer["navigationEndpoint"])
            ?? videoID(fromNavigationEndpointIn: renderer["rendererContext"])
    }

    private static func videoID(fromNavigationEndpointIn value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let dictionary = value as? [String: Any] {
            if let watchEndpoint = dictionary["watchEndpoint"] as? [String: Any],
               let videoID = nonEmptyString(watchEndpoint["videoId"]) {
                return videoID
            }

            if let commandMetadata = dictionary["commandMetadata"] as? [String: Any],
               let webCommandMetadata = commandMetadata["webCommandMetadata"] as? [String: Any],
               let url = nonEmptyString(webCommandMetadata["url"]),
               let videoID = videoID(fromURLString: url) {
                return videoID
            }

            for child in dictionary.values {
                if let videoID = videoID(fromNavigationEndpointIn: child) {
                    return videoID
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let videoID = videoID(fromNavigationEndpointIn: child) {
                    return videoID
                }
            }
        }

        return nil
    }

    private static func videoID(fromURLString string: String) -> String? {
        var candidate = string
        if candidate.hasPrefix("/") {
            candidate = "https://www.youtube.com" + candidate
        }

        guard let components = URLComponents(string: candidate) else {
            return nil
        }

        if components.path == "/watch" {
            return components.queryItems?.first { $0.name == "v" }?.value
        }

        if components.path.hasPrefix("/shorts/") {
            return components.path.split(separator: "/").last.map(String.init)
        }

        return nil
    }

    private static func title(from renderer: [String: Any]) -> String? {
        text(from: renderer["title"])
            ?? text(from: renderer["headline"])
            ?? text(from: renderer["titleText"])
            ?? text(at: ["metadata", "lockupMetadataViewModel", "title"], in: renderer)
    }

    private static func channelTitle(from renderer: [String: Any]) -> String? {
        text(from: renderer["shortBylineText"])
            ?? text(from: renderer["ownerText"])
            ?? text(from: renderer["longBylineText"])
            ?? text(at: ["metadata", "lockupMetadataViewModel", "metadata"], in: renderer)
    }

    private static func durationText(from renderer: [String: Any]) -> String? {
        text(from: renderer["lengthText"])
            ?? text(from: renderer["thumbnailOverlays"])
            ?? text(at: ["contentImage", "collectionThumbnailViewModel", "primaryThumbnail", "thumbnailOverlays"], in: renderer)
    }

    private static func viewCountText(from renderer: [String: Any]) -> String? {
        text(from: renderer["shortViewCountText"])
            ?? text(from: renderer["viewCountText"])
            ?? textContaining("view", in: renderer["videoInfo"])
            ?? textContaining("view", in: renderer["metadata"])
    }

    private static func publishedText(from renderer: [String: Any]) -> String? {
        text(from: renderer["publishedTimeText"])
            ?? textContaining("ago", in: renderer["videoInfo"])
            ?? textContaining("ago", in: renderer["metadata"])
    }

    private static func text(at path: [String], in dictionary: [String: Any]) -> String? {
        var value: Any? = dictionary

        for key in path {
            guard let current = value as? [String: Any] else {
                return nil
            }

            value = current[key]
        }

        return text(from: value)
    }

    private static func textContaining(_ needle: String, in value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let string = text(from: value),
           string.localizedCaseInsensitiveContains(needle) {
            return string
        }

        if let dictionary = value as? [String: Any] {
            for child in dictionary.values {
                if let text = textContaining(needle, in: child) {
                    return text
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let text = textContaining(needle, in: child) {
                    return text
                }
            }
        }

        return nil
    }

    private static func text(from value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let string = value as? String {
            return nonEmptyText(string)
        }

        if let dictionary = value as? [String: Any] {
            if let simpleText = nonEmptyString(dictionary["simpleText"]) {
                return simpleText
            }

            if let content = nonEmptyString(dictionary["content"]) {
                return content
            }

            if let accessibilityData = dictionary["accessibilityData"] as? [String: Any],
               let label = nonEmptyString(accessibilityData["label"]) {
                return label
            }

            if let accessibility = dictionary["accessibility"] as? [String: Any],
               let text = text(from: accessibility) {
                return text
            }

            if let runs = dictionary["runs"] as? [Any] {
                let joinedRuns = runs
                    .compactMap { run -> String? in
                        guard let run = run as? [String: Any] else {
                            return nil
                        }

                        return run["text"] as? String
                    }
                    .joined()

                if let joinedText = nonEmptyText(joinedRuns) {
                    return joinedText
                }
            }

            for key in ["text", "title", "subtitle", "caption"] {
                if let text = text(from: dictionary[key]) {
                    return text
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let text = text(from: child) {
                    return text
                }
            }
        }

        return nil
    }

    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let value else {
            return nil
        }

        if let dictionary = value as? [String: Any] {
            if let thumbnails = dictionary["thumbnails"] as? [Any],
               let url = thumbnailURL(fromThumbnails: thumbnails) {
                return url
            }

            if let url = url(from: dictionary["url"]) {
                return url
            }

            for child in dictionary.values {
                if let url = thumbnailURL(from: child) {
                    return url
                }
            }
        } else if let array = value as? [Any] {
            if let url = thumbnailURL(fromThumbnails: array) {
                return url
            }

            for child in array {
                if let url = thumbnailURL(from: child) {
                    return url
                }
            }
        }

        return nil
    }

    private static func thumbnailURL(fromThumbnails thumbnails: [Any]) -> URL? {
        thumbnails
            .reversed()
            .compactMap { thumbnail -> URL? in
                guard let thumbnail = thumbnail as? [String: Any] else {
                    return nil
                }

                return url(from: thumbnail["url"])
            }
            .first
    }

    private static func url(from value: Any?) -> URL? {
        guard var string = nonEmptyString(value) else {
            return nil
        }

        if string.hasPrefix("//") {
            string = "https:" + string
        } else if string.hasPrefix("/") {
            string = "https://www.youtube.com" + string
        }

        return URL(string: string)
    }

    private static func fallbackThumbnailURL(videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    private static func continuation(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let nextContinuationData = dictionary["nextContinuationData"] as? [String: Any],
               let continuation = nonEmptyString(nextContinuationData["continuation"]) {
                return continuation
            }

            if let continuationCommand = dictionary["continuationCommand"] as? [String: Any],
               let continuation = nonEmptyString(continuationCommand["token"])
                ?? nonEmptyString(continuationCommand["continuation"]) {
                return continuation
            }

            for child in dictionary.values {
                if let continuation = continuation(from: child) {
                    return continuation
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let continuation = continuation(from: child) {
                    return continuation
                }
            }
        }

        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        if let string = value as? String {
            return nonEmptyText(string)
        }

        if let integer = value as? Int {
            return String(integer)
        }

        return nil
    }

    private static func nonEmptyText(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private nonisolated struct SearchResponse: Decodable {
    let contents: SearchContents?
    let onResponseReceivedCommands: [SearchResponseCommand]?

    var searchPage: SearchPage {
        let sectionListRenderer = contents?
            .twoColumnSearchResultsRenderer?
            .primaryContents?
            .sectionListRenderer
        let firstPageItems = sectionListRenderer?.contents ?? []
        let continuationItems = onResponseReceivedCommands?
            .flatMap { $0.appendContinuationItemsAction?.continuationItems ?? [] } ?? []
        let allItems = firstPageItems + continuationItems

        var seenVideoIDs = Set<String>()
        let videos = allItems
            .flatMap(\.videos)
            .filter { seenVideoIDs.insert($0.id).inserted }

        let continuation = sectionListRenderer?
            .continuations?
            .compactMap { $0.nextContinuationData?.continuation }
            .first
            ?? allItems.compactMap(\.continuation).first

        return SearchPage(videos: videos, continuation: continuation)
    }
}

private nonisolated struct SearchContents: Decodable {
    let twoColumnSearchResultsRenderer: TwoColumnSearchResultsRenderer?
}

private nonisolated struct TwoColumnSearchResultsRenderer: Decodable {
    let primaryContents: SearchPrimaryContents?
}

private nonisolated struct SearchPrimaryContents: Decodable {
    let sectionListRenderer: SectionListRenderer?
}

private nonisolated struct SectionListRenderer: Decodable {
    let contents: [SearchItem]?
    let continuations: [SearchContinuation]?
}

private nonisolated struct SearchItem: Decodable {
    let itemSectionRenderer: ItemSectionRenderer?
    let videoRenderer: VideoRenderer?
    let continuationItemRenderer: ContinuationItemRenderer?

    var videos: [Video] {
        var videos = itemSectionRenderer?.contents?.flatMap(\.videos) ?? []

        if let video = videoRenderer?.video {
            videos.append(video)
        }

        return videos
    }

    var continuation: String? {
        continuationItemRenderer?
            .continuationEndpoint?
            .continuationCommand?
            .token
            ?? itemSectionRenderer?.contents?.compactMap(\.continuation).first
    }
}

private nonisolated struct ItemSectionRenderer: Decodable {
    let contents: [SearchItem]?
}

private nonisolated struct VideoRenderer: Decodable {
    let videoID: String?
    let title: SearchText?
    let ownerText: SearchText?
    let longBylineText: SearchText?
    let lengthText: SearchText?
    let viewCountText: SearchText?
    let shortViewCountText: SearchText?
    let publishedTimeText: SearchText?
    let thumbnail: ThumbnailRenderer?

    var video: Video? {
        guard let videoID,
              let title = title?.plainText,
              !title.isEmpty else {
            return nil
        }

        return Video(
            id: videoID,
            title: title,
            channelTitle: ownerText?.plainText ?? longBylineText?.plainText,
            durationText: lengthText?.plainText,
            viewCountText: shortViewCountText?.plainText ?? viewCountText?.plainText,
            publishedText: publishedTimeText?.plainText,
            thumbnailURL: thumbnail?.bestURL ?? Self.fallbackThumbnailURL(videoID: videoID)
        )
    }

    private static func fallbackThumbnailURL(videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    private enum CodingKeys: String, CodingKey {
        case videoID = "videoId"
        case title
        case ownerText
        case longBylineText
        case lengthText
        case viewCountText
        case shortViewCountText
        case publishedTimeText
        case thumbnail
    }
}

private nonisolated struct SearchText: Decodable {
    let simpleText: String?
    let runs: [SearchTextRun]?

    var plainText: String? {
        let text = simpleText ?? runs?.map(\.text).joined()
        return text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }
}

private nonisolated struct SearchTextRun: Decodable {
    let text: String
}

private nonisolated struct ThumbnailRenderer: Decodable {
    let thumbnails: [Thumbnail]?

    var bestURL: URL? {
        thumbnails?
            .compactMap { Self.normalizedURL(from: $0.url) }
            .last
    }

    private static func normalizedURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }

        return URL(string: value)
    }
}

private nonisolated struct Thumbnail: Decodable {
    let url: String?
}

private nonisolated struct SearchContinuation: Decodable {
    let nextContinuationData: NextContinuationData?
}

private nonisolated struct NextContinuationData: Decodable {
    let continuation: String?
}

private nonisolated struct ContinuationItemRenderer: Decodable {
    let continuationEndpoint: ContinuationEndpoint?
}

private nonisolated struct ContinuationEndpoint: Decodable {
    let continuationCommand: ContinuationCommand?
}

private nonisolated struct ContinuationCommand: Decodable {
    let token: String?
}

private nonisolated struct SearchResponseCommand: Decodable {
    let appendContinuationItemsAction: AppendContinuationItemsAction?
}

private nonisolated struct AppendContinuationItemsAction: Decodable {
    let continuationItems: [SearchItem]?
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
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
            URLQueryItem(name: "alt", value: "json"),
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
    case fallbackFailed(primary: Error, fallback: Error)
    case missingAuthCookie(String)

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
        case .fallbackFailed(let primary, let fallback):
            [
                "YouTube fallback failed.",
                "Primary error: \(primary.localizedDescription)",
                "Watch page error: \(fallback.localizedDescription)",
            ].joined(separator: " ")
        case .missingAuthCookie(let cookieName):
            "Missing YouTube auth cookie: \(cookieName)."
        }
    }
}

private extension PlayerResponse {
    nonisolated var hasHLSStream: Bool {
        playabilityStatus?.status == "OK" && StreamExtractor.hasSupportedHLSStream(from: self)
    }

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
