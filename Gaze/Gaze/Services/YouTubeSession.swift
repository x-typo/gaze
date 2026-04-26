import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class YouTubeSession {
    private(set) var isSignedIn = false
    private(set) var isVerifyingSession = false
    private(set) var statusMessage: String?

    @ObservationIgnored private let cookieStorage: HTTPCookieStorage

    init(cookieStorage: HTTPCookieStorage = .shared) {
        self.cookieStorage = cookieStorage
        restoreSession()
    }

    func restoreSession() {
        isSignedIn = Self.hasSignInCookies(cookieStorage.cookies ?? [])
        statusMessage = nil
    }

    func authContext() throws -> YouTubeAuthContext {
        let cookies = cookieStorage.cookies ?? []
        guard let sapisid = Self.sapisidValue(in: cookies) else {
            throw YouTubeError.missingAuthCookie("SAPISID or __Secure-3PAPISID")
        }

        guard let cookieHeader = Self.cookieHeader(
            from: cookies,
            for: Self.innertubeRequestURL
        ) else {
            throw YouTubeSessionError.missingCookieHeader
        }

        guard let nativePageCookieHeader = Self.cookieHeader(
            from: cookies,
            for: Self.playlistsPageURL
        ) else {
            throw YouTubeSessionError.missingCookieHeader
        }

        return YouTubeAuthContext(
            sapisid: sapisid,
            cookieHeader: cookieHeader,
            nativePageCookieHeader: nativePageCookieHeader
        )
    }

    func refreshedAuthContext() async throws -> YouTubeAuthContext {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        syncCookies(await Self.allCookies(from: cookieStore))
        return try authContext()
    }

    func refreshedPlaylistAuthContext() async throws -> YouTubeAuthContext {
        try await refreshFirstPartyYouTubeSession()
        return try await refreshedAuthContext()
    }

    func inspectAuthCookies() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        syncCookies(await Self.allCookies(from: cookieStore))

        let diagnostics = Self.authDiagnostics(from: cookieStorage.cookies ?? [])
        isSignedIn = diagnostics.hasMinimumAuthCookies
        statusMessage = diagnostics.summary
    }

    func handleLoginNavigation(url: URL?, cookies: [HTTPCookie]) -> Bool {
        syncCookies(cookies)

        guard Self.isYouTubeURL(url),
              Self.hasSAPISID(cookies) else {
            return false
        }

        isSignedIn = true
        statusMessage = nil
        return true
    }

    func signOut() async {
        await clearStoredSession()
        statusMessage = nil
    }

    private func clearStoredSession() async {
        let cookies = cookieStorage.cookies ?? []
        cookies
            .filter(Self.shouldManageCookie)
            .forEach(cookieStorage.deleteCookie)

        await deleteWebViewCookies()
        isSignedIn = false
    }

    func verifyAuthenticatedSession() async {
        guard !isVerifyingSession else {
            return
        }

        let authContext: YouTubeAuthContext
        do {
            authContext = try await refreshedAuthContext()
        } catch {
            await clearStoredSession()
            statusMessage = error.localizedDescription
            return
        }

        isVerifyingSession = true
        statusMessage = nil
        defer {
            isVerifyingSession = false
        }

        do {
            let result = try await YouTubeClient.shared.authenticatedSessionProbe(
                sapisid: authContext.sapisid,
                cookieHeader: authContext.cookieHeader
            )
            let pageResult = try await YouTubeClient.shared.nativePlaylistPageProbe(
                authContext: authContext
            )

            guard !pageResult.wasRedirectedToSignIn else {
                await clearStoredSession()
                statusMessage = [
                    "YouTube rejected the stored session.",
                    "Native playlist page probe redirected to",
                    "\(pageResult.finalHost ?? "unknown")\(pageResult.finalPath ?? "").",
                    "Sign in again from Settings.",
                ].joined(separator: " ")
                return
            }

            isSignedIn = true
            statusMessage = [
                "Innertube account probe accepted by YouTube (\(result.responseByteCount) bytes).",
                "Native playlist page probe: \(pageResult.responseByteCount) bytes,",
                "final \(pageResult.finalHost ?? "unknown")\(pageResult.finalPath ?? ""),",
                "sign-in redirect \(pageResult.wasRedirectedToSignIn ? "yes" : "no").",
            ].joined(separator: " ")
        } catch {
            if Self.isAuthRejection(error) {
                await clearStoredSession()
            }

            statusMessage = error.localizedDescription
        }
    }

    private func syncCookies(_ cookies: [HTTPCookie]) {
        cookies
            .filter(Self.shouldManageCookie)
            .forEach(cookieStorage.setCookie)
    }

    private func deleteWebViewCookies() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await Self.allCookies(from: cookieStore)

        for cookie in cookies where Self.shouldManageCookie(cookie) {
            await Self.delete(cookie, from: cookieStore)
        }
    }

    private func refreshFirstPartyYouTubeSession() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = YouTubeCookieRefreshNavigationDelegate()
        webView.navigationDelegate = delegate
        webView.customUserAgent = Self.desktopSafariUserAgent

        var request = URLRequest(url: Self.playlistsRefreshURL)
        request.setValue(Self.desktopSafariUserAgent, forHTTPHeaderField: "User-Agent")

        try await delegate.load(request, in: webView)
    }

    private static func hasSignInCookies(_ cookies: [HTTPCookie]) -> Bool {
        hasSAPISID(cookies) && hasSID(cookies)
    }

    private static func hasSAPISID(_ cookies: [HTTPCookie]) -> Bool {
        sapisidValue(in: cookies) != nil
    }

    private static func hasSID(_ cookies: [HTTPCookie]) -> Bool {
        cookieValue(named: "SID", in: cookies) != nil
            || cookieValue(named: "__Secure-3PSID", in: cookies) != nil
            || cookieValue(named: "__Secure-1PSID", in: cookies) != nil
    }

    private static func sapisidValue(in cookies: [HTTPCookie]) -> String? {
        cookieValue(named: "__Secure-3PAPISID", in: cookies)
            ?? cookieValue(named: "__Secure-1PAPISID", in: cookies)
            ?? cookieValue(named: "SAPISID", in: cookies)
    }

    private static func authDiagnostics(from cookies: [HTTPCookie]) -> YouTubeAuthDiagnostics {
        let managedCookies = cookies.filter(shouldManageCookie)
        let youtubeCookieCount = managedCookies
            .filter { $0.domain.lowercased().contains("youtube.com") }
            .count
        let googleCookieCount = managedCookies
            .filter { $0.domain.lowercased().contains("google.com") }
            .count
        let cookieNames = Set(managedCookies.map(\.name))
        let cookieHeaderByteCount = cookieHeader(from: cookies, for: innertubeRequestURL)?
            .data(using: .utf8)?
            .count

        return YouTubeAuthDiagnostics(
            sapisidCookieName: firstCookieName(
                in: cookies,
                names: ["__Secure-3PAPISID", "__Secure-1PAPISID", "SAPISID"]
            ),
            hasPlainSAPISID: cookieValue(named: "SAPISID", in: cookies) != nil,
            sidCookieName: firstCookieName(
                in: cookies,
                names: ["__Secure-3PSID", "__Secure-1PSID", "SID"]
            ),
            hasLoginInfo: cookieNames.contains("LOGIN_INFO"),
            managedCookieCount: managedCookies.count,
            youtubeCookieCount: youtubeCookieCount,
            googleCookieCount: googleCookieCount,
            cookieHeaderByteCount: cookieHeaderByteCount
        )
    }

    private static func firstCookieName(in cookies: [HTTPCookie], names: [String]) -> String? {
        names.first { name in
            cookieValue(named: name, in: cookies) != nil
        }
    }

    private static func cookieValue(named name: String, in cookies: [HTTPCookie]) -> String? {
        cookies.first { cookie in
            cookie.name == name && !cookie.value.isEmpty
        }?.value
    }

    private static func cookieHeader(from cookies: [HTTPCookie], for url: URL) -> String? {
        let managedCookies = cookies.filter {
            shouldManageCookie($0) && cookie($0, matches: url)
        }
        let header = HTTPCookie.requestHeaderFields(with: managedCookies)["Cookie"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let header, !header.isEmpty else {
            return nil
        }

        return header
    }

    private static func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        if cookie.isSecure && url.scheme?.lowercased() != "https" {
            return false
        }

        let cookieDomain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host == cookieDomain || host.hasSuffix(".\(cookieDomain)") else {
            return false
        }

        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        return requestPath == cookiePath
            || requestPath.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : "\(cookiePath)/")
    }

    private static func isAuthRejection(_ error: Error) -> Bool {
        if case YouTubeError.http(let statusCode, _) = error,
           statusCode == 401 || statusCode == 403 {
            return true
        }

        return false
    }

    private static func shouldManageCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain.contains("youtube.com") || domain.contains("google.com")
    }

    private static func isYouTubeURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }

        return host == "youtube.com"
            || host == "www.youtube.com"
            || host == "m.youtube.com"
            || host.hasSuffix(".youtube.com")
    }

    private static func allCookies(from cookieStore: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func delete(
        _ cookie: HTTPCookie,
        from cookieStore: WKHTTPCookieStore
    ) async {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private nonisolated static let playlistsRefreshURL = URL(
        string: "https://www.youtube.com/feed/playlists?persist_app=1&app=desktop"
    )!

    private nonisolated static let innertubeRequestURL = URL(
        string: "https://www.youtube.com/youtubei/v1/browse"
    )!

    private nonisolated static let playlistsPageURL = URL(
        string: "https://www.youtube.com/feed/playlists"
    )!

    private nonisolated static let desktopSafariUserAgent = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.0 Safari/605.1.15",
    ].joined(separator: " ")
}

private final class YouTubeCookieRefreshNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ request: URLRequest, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: error)
    }

    private func finish(with error: Error? = nil) {
        guard let continuation else {
            return
        }

        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

private nonisolated enum YouTubeSessionError: LocalizedError {
    case missingCookieHeader

    var errorDescription: String? {
        switch self {
        case .missingCookieHeader:
            "No YouTube or Google cookies are available for authenticated requests."
        }
    }
}

private nonisolated struct YouTubeAuthDiagnostics: Sendable {
    let sapisidCookieName: String?
    let hasPlainSAPISID: Bool
    let sidCookieName: String?
    let hasLoginInfo: Bool
    let managedCookieCount: Int
    let youtubeCookieCount: Int
    let googleCookieCount: Int
    let cookieHeaderByteCount: Int?

    var hasMinimumAuthCookies: Bool {
        sapisidCookieName != nil && sidCookieName != nil && cookieHeaderByteCount != nil
    }

    var summary: String {
        [
            "Auth cookies only; no values shown.",
            "SAPI: \(sapisidCookieName ?? "missing")",
            "Plain SAPISID: \(hasPlainSAPISID ? "present" : "missing")",
            "SID: \(sidCookieName ?? "missing")",
            "LOGIN_INFO: \(hasLoginInfo ? "present" : "missing")",
            "Cookie header: \(cookieHeaderByteCount.map { "\($0) bytes" } ?? "missing")",
            "Managed cookies: \(managedCookieCount) total, \(youtubeCookieCount) YouTube, \(googleCookieCount) Google.",
        ].joined(separator: " ")
    }
}
