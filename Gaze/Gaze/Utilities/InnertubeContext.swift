import Foundation

nonisolated struct InnertubeBootstrap: Codable, Sendable {
    let apiKey: String
    let clientVersion: String
    let visitorData: String?
    let fetchedAt: Date

    var isFresh: Bool {
        let age = Date().timeIntervalSince(fetchedAt)
        return age >= 0 && age < 24 * 60 * 60
    }
}

actor InnertubeContextProvider {
    static let shared = InnertubeContextProvider()

    private static let cacheKey = "gaze.innertube.bootstrap.v1"

    private let session: URLSession
    private let defaults: UserDefaults
    private var inMemoryBootstrap: InnertubeBootstrap?

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.defaults = defaults
    }

    func bootstrap() async throws -> InnertubeBootstrap {
        if let inMemoryBootstrap, inMemoryBootstrap.isFresh {
            return inMemoryBootstrap
        }

        if let cachedBootstrap, cachedBootstrap.isFresh {
            inMemoryBootstrap = cachedBootstrap
            return cachedBootstrap
        }

        do {
            let freshBootstrap = try await fetchBootstrap()
            cache(freshBootstrap)
            inMemoryBootstrap = freshBootstrap
            return freshBootstrap
        } catch {
            if let cachedBootstrap {
                inMemoryBootstrap = cachedBootstrap
                return cachedBootstrap
            }

            throw error
        }
    }

    func context() async throws -> InnertubeContext {
        let bootstrap = try await bootstrap()
        return InnertubeContext(
            client: InnertubeClientContext(
                clientName: "WEB",
                clientVersion: bootstrap.clientVersion,
                hl: "en",
                gl: "US",
                visitorData: bootstrap.visitorData
            )
        )
    }

    func androidVRContext() async throws -> InnertubeContext {
        let bootstrap = try await bootstrap()
        return InnertubeContext(
            client: InnertubeClientContext(
                clientName: "ANDROID_VR",
                clientVersion: Self.androidVRClientVersion,
                hl: "en",
                gl: "US",
                visitorData: bootstrap.visitorData,
                deviceMake: "Oculus",
                deviceModel: "Quest 3",
                androidSdkVersion: 32,
                userAgent: Self.androidVRUserAgent,
                osName: "Android",
                osVersion: "12L"
            )
        )
    }

    private var cachedBootstrap: InnertubeBootstrap? {
        guard let data = defaults.data(forKey: Self.cacheKey) else {
            return nil
        }

        return try? JSONDecoder().decode(InnertubeBootstrap.self, from: data)
    }

    private func cache(_ bootstrap: InnertubeBootstrap) {
        guard let data = try? JSONEncoder().encode(bootstrap) else {
            return
        }

        defaults.set(data, forKey: Self.cacheKey)
    }

    private func fetchBootstrap() async throws -> InnertubeBootstrap {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnertubeBootstrapError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw InnertubeBootstrapError.httpStatus(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw InnertubeBootstrapError.invalidUTF8
        }

        let apiKey = try extractJSONStringValue(named: "INNERTUBE_API_KEY", from: html)
        let clientVersion = try extractJSONStringValue(named: "INNERTUBE_CLIENT_VERSION", from: html)
        let visitorData = try? extractJSONStringValue(named: "VISITOR_DATA", from: html)

        return InnertubeBootstrap(
            apiKey: apiKey,
            clientVersion: clientVersion,
            visitorData: visitorData,
            fetchedAt: Date()
        )
    }

    private func extractJSONStringValue(named name: String, from text: String) throws -> String {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: name))\"\\s*:\\s*\"([^\"]+)\""
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            throw InnertubeBootstrapError.missingConfigValue(name)
        }

        return String(text[valueRange])
    }

    nonisolated private static let userAgent = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.0 Safari/605.1.15",
    ].joined(separator: " ")

    nonisolated static let androidVRClientVersion = "1.65.10"

    nonisolated static let androidVRUserAgent = [
        "com.google.android.apps.youtube.vr.oculus/1.65.10",
        "(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
    ].joined(separator: " ")
}

nonisolated enum InnertubeBootstrapError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidUTF8
    case missingConfigValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "YouTube bootstrap did not return an HTTP response."
        case .httpStatus(let statusCode):
            "YouTube bootstrap failed with HTTP \(statusCode)."
        case .invalidUTF8:
            "YouTube bootstrap response was not valid UTF-8 text."
        case .missingConfigValue(let name):
            "YouTube bootstrap response did not include \(name)."
        }
    }
}
