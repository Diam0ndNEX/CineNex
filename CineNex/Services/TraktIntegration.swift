import Combine
import Foundation
import Security

struct TraktDeviceAuthorization: Decodable, Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TraktTokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let createdAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case createdAt = "created_at"
    }

    var expirationDate: Date {
        Date(timeIntervalSince1970: createdAt + TimeInterval(expiresIn))
    }
}

private struct TraktAPIError: LocalizedError {
    let statusCode: Int
    let responseText: String

    var errorDescription: String? {
        if statusCode == 401 {
            return "Trakt authorization expired or was rejected. Disconnect and connect the account again."
        }
        if statusCode == 429 {
            return "Trakt rate limit reached. Wait a little before trying again."
        }
        return "Trakt returned HTTP \(statusCode). \(responseText)"
    }
}

@MainActor
final class TraktIntegration: ObservableObject {
    static let shared = TraktIntegration()

    @Published private(set) var isConnected = false
    @Published private(set) var statusMessage = "Not connected"
    @Published private(set) var lastError: String?
    @Published private(set) var isAuthorizing = false
    @Published private(set) var activeAuthorization: TraktDeviceAuthorization?

    private let defaults: UserDefaults
    private let clientIDKey = "cinenex.trakt.clientID"
    private let tokenStore = TraktTokenKeychain()
    private var tokens: TraktTokenResponse?
    private var refreshTask: Task<TraktTokenResponse, Error>?
    private var authenticationGeneration = UUID()
    private var deviceLoginTask: Task<Void, Never>?

    var savedClientID: String {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "CINENEX_TRAKT_CLIENT_ID") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !configured.isEmpty && !configured.hasPrefix("$(") ? configured : (defaults.string(forKey: clientIDKey) ?? "")
    }

    init(defaults: UserDefaults = .standard, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.browserTokenSession = session
        self.defaults = defaults
        self.tokens = try? tokenStore.load()
        self.isConnected = tokens != nil
        self.statusMessage = tokens == nil ? "Not connected" : "Trakt account connected"
    }

    private let webLogin = AnimeWebLogin()
    private let browserTokenSession: URLSession
    private var redirectURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CINENEX_TRAKT_REDIRECT_URI") as? String else { return nil }
        return TraktOAuthPolicy.validRedirect(value)
    }
    var loginAvailable: Bool { !savedClientID.isEmpty }
    var browserLoginAvailable: Bool { loginAvailable && redirectURL != nil }

    func signInWithBrowser() async {
        guard !isAuthorizing else { return }
        guard browserLoginAvailable else {
            lastError = "Trakt login is not enabled in this build. CineNex needs its registered app and associated HTTPS callback configured by the developer; you do not need an API key."
            return
        }
        isAuthorizing = true
        refreshTask?.cancel()
        refreshTask = nil
        let generation = UUID()
        authenticationGeneration = generation
        defer { isAuthorizing = false }
        statusMessage = "Opening Trakt sign-in…"
        lastError = nil
        do {
            let state = try AnimeOAuthPolicy.randomVerifier()
            let verifier = try AnimeOAuthPolicy.randomVerifier()
            guard let redirect = redirectURL else { throw IntegrationError.message("Trakt requires a registered HTTPS callback.") }
            let authorize = try TraktOAuthPolicy.authorizationURL(clientID: savedClientID, redirect: redirect, verifier: verifier, state: state)
            let response = try await webLogin.authorize(authorize, callback: redirect)
            guard authenticationGeneration == generation else { throw CancellationError() }
            let values = try AnimeOAuthPolicy.callbackValues(response, expected: redirect, state: state)
            guard let code = values["code"], !code.isEmpty else { throw IntegrationError.message("Trakt did not return an authorization code.") }
            let token = try await exchangeToken(["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": redirect.absoluteString])
            guard authenticationGeneration == generation else { throw CancellationError() }
            try tokenStore.save(token)
            tokens = token
            isConnected = true
            statusMessage = "Trakt account connected"
        } catch { lastError = error.localizedDescription; statusMessage = "Trakt sign-in did not finish" }
    }

    private func exchangeToken(_ fields: [String: String]) async throws -> TraktTokenResponse {
        let request = try TraktOAuthPolicy.tokenRequest(fields, clientID: savedClientID)
        let (data, response) = try await browserTokenSession.data(for: request, delegate: AccountNoRedirectDelegate())
        guard let http = response as? HTTPURLResponse, data.count < 100_000 else { throw IntegrationError.message("Trakt returned an invalid sign-in response.") }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["error"] as? String == "invalid_grant" { throw TokenExchangeError.reauthorizationRequired }
            throw IntegrationError.message("Trakt sign-in was rejected (HTTP \(http.statusCode)). Try again later.")
        }
        let token = try JSONDecoder().decode(TraktTokenResponse.self, from: data)
        guard !token.accessToken.isEmpty, !token.refreshToken.isEmpty, token.expiresIn > 0 else { throw IntegrationError.message("Trakt returned an invalid session.") }
        return token
    }

    private enum TokenExchangeError: LocalizedError {
        case reauthorizationRequired
        var errorDescription: String? { "Your Trakt session expired. Sign in again to reconnect." }
    }

    func saveClientID(_ clientID: String) {
        defaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey)
        lastError = nil
    }

    /// Device authorization survives IPA re-signing; no callback domain or client secret is needed.
    func startDeviceSignIn() {
        guard !isAuthorizing else { return }
        guard loginAvailable else {
            lastError = "Trakt login is not configured in this build. No API key is required from you."
            return
        }
        let generation = UUID()
        authenticationGeneration = generation
        refreshTask?.cancel()
        refreshTask = nil
        isAuthorizing = true
        activeAuthorization = nil
        lastError = nil
        statusMessage = "Requesting a Trakt sign-in code…"
        deviceLoginTask = Task { await performDeviceSignIn(generation: generation) }
    }

    func cancelDeviceSignIn() {
        guard deviceLoginTask != nil else { return }
        authenticationGeneration = UUID()
        deviceLoginTask?.cancel()
        deviceLoginTask = nil
        activeAuthorization = nil
        isAuthorizing = false
        lastError = nil
        statusMessage = isConnected ? "Trakt account connected" : "Sign-in cancelled"
    }

    private func performDeviceSignIn(generation: UUID) async {
        defer {
            if authenticationGeneration == generation {
                isAuthorizing = false
                activeAuthorization = nil
                deviceLoginTask = nil
            }
        }
        do {
            let clientID = savedClientID
            let authorization: TraktDeviceAuthorization = try await post(
                path: "/oauth/device/code", body: ["client_id": clientID], clientID: clientID,
                bearerToken: nil, acceptsPendingAuthorization: false)
            try Task.checkCancellation()
            guard authenticationGeneration == generation else { return }
            guard TraktOAuthPolicy.validDeviceAuthorization(authorization) else {
                throw IntegrationError.message("Trakt returned an invalid sign-in code or verification address.")
            }
            activeAuthorization = authorization
            statusMessage = "Open Trakt, enter the code, then return here."
            var delay = authorization.interval
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(authorization.expiresIn))
            while clock.now < deadline {
                try await Task.sleep(for: min(.seconds(delay), clock.now.duration(to: deadline)))
                try Task.checkCancellation()
                guard authenticationGeneration == generation else { return }
                guard clock.now < deadline else { break }
                do {
                    let token: TraktTokenResponse = try await post(
                        path: "/oauth/device/token", body: ["code": authorization.deviceCode, "client_id": clientID],
                        clientID: clientID, bearerToken: nil, acceptsPendingAuthorization: true)
                    try Task.checkCancellation()
                    guard authenticationGeneration == generation else { return }
                    guard clock.now < deadline else { break }
                    guard !token.accessToken.isEmpty, !token.refreshToken.isEmpty, token.expiresIn > 0 else {
                        throw IntegrationError.message("Trakt returned an invalid session.")
                    }
                    try tokenStore.save(token)
                    tokens = token
                    isConnected = true
                    statusMessage = "Trakt account connected"
                    return
                } catch let error as DeviceAuthorizationPendingError {
                    if error.slowDown { delay = min(delay + 5, 86_400) }
                }
            }
            throw IntegrationError.message("The sign-in code expired. Start sign-in again for a new code.")
        } catch {
            guard authenticationGeneration == generation else { return }
            if Task.isCancelled || error is CancellationError {
                statusMessage = "Sign-in cancelled"
            } else {
                lastError = error.localizedDescription
                statusMessage = "Trakt sign-in did not finish"
            }
        }
    }

    func reportSetupError(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = "Trakt connection failed"
    }

    func disconnect() {
        cancelDeviceSignIn()
        authenticationGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        try? tokenStore.delete()
        tokens = nil
        isConnected = false
        activeAuthorization = nil
        statusMessage = "Not connected"
        lastError = nil
    }

    func fetchMovieWatchlist() async throws -> [TraktWatchlistMovie] {
        guard isConnected else {
            throw IntegrationError.message("Connect your Trakt account before importing its watchlist.")
        }
        let token = try await validAccessToken()
        let data = try await get(
            path: "/sync/watchlist/movies",
            clientID: savedClientID,
            bearerToken: token.accessToken
        )
        let movies = try TraktWatchlistMovie.decodeList(data)
        statusMessage = "Loaded \(movies.count) movies from your Trakt watchlist"
        lastError = nil
        return movies
    }

    func fetchMovieHistory() async throws -> [TraktHistoryMovie] {
        guard isConnected else {
            throw IntegrationError.message("Connect your Trakt account before importing its watch history.")
        }
        let token = try await validAccessToken()
        let data = try await get(
            path: "/sync/history/movies",
            clientID: savedClientID,
            bearerToken: token.accessToken
        )
        let movies = try TraktHistoryMovie.decodeList(data)
        statusMessage = "Loaded history for \(movies.count) movies from Trakt"
        lastError = nil
        return movies
    }

    func fetchMovieRatings() async throws -> [TraktRatingMovie] {
        guard isConnected else {
            throw IntegrationError.message("Connect your Trakt account before importing your ratings.")
        }
        let token = try await validAccessToken()
        let data = try await get(
            path: "/sync/ratings/movies",
            clientID: savedClientID,
            bearerToken: token.accessToken
        )
        let movies = try TraktRatingMovie.decodeList(data)
        statusMessage = "Loaded ratings for \\(movies.count) movies from Trakt"
        lastError = nil
        return movies
    }

    func scrobbleStart(for item: MediaItem) async {
        await sendScrobble("start", for: item, position: 0, duration: 0)
    }

    func scrobbleStop(for item: MediaItem, position: Double, duration: Double) async {
        await sendScrobble("stop", for: item, position: position, duration: duration)
    }

    private func sendScrobble(_ action: String, for item: MediaItem, position: Double, duration: Double) async {
        guard defaults.bool(forKey: "cinenex.traktScrobbleEnabled"), isConnected else { return }
        guard item.kind == .movie else {
            statusMessage = "Trakt scrobbling for episodes will be enabled when episode metadata is available."
            return
        }

        do {
            let token = try await validAccessToken()
            let movie = TraktScrobbleMetadata.moviePayload(for: item)
            let progress: Double
            if duration.isFinite, duration > 0, position.isFinite {
                progress = min(100, max(0, position / duration * 100))
            } else {
                progress = 0
            }
            let _: EmptyResponse = try await post(
                path: "/scrobble/\(action)",
                body: ["movie": movie, "progress": progress],
                clientID: savedClientID,
                bearerToken: token.accessToken,
                acceptsPendingAuthorization: false
            )
            statusMessage = action == "start" ? "Tracking playback with Trakt" : "Playback sent to Trakt"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func validAccessToken() async throws -> TraktTokenResponse {
        guard let current = tokens else {
            throw IntegrationError.message("Connect your Trakt account to enable watch tracking.")
        }
        if current.expirationDate.timeIntervalSinceNow > 90 {
            return current
        }

        // Trakt refresh tokens are single-use: concurrent API calls must share one refresh.
        if let refreshTask { return try await refreshTask.value }
        let generation = authenticationGeneration
        let task = Task { @MainActor in
            let refreshed: TraktTokenResponse
            do { refreshed = try await exchangeToken(["grant_type": "refresh_token", "refresh_token": current.refreshToken]) }
            catch {
                if authenticationGeneration == generation, error is TokenExchangeError {
                    try? tokenStore.delete()
                    tokens = nil
                    isConnected = false
                    statusMessage = "Sign in to reconnect Trakt"
                }
                throw error
            }
            guard authenticationGeneration == generation else { throw CancellationError() }
            try tokenStore.save(refreshed)
            tokens = refreshed
            return refreshed
        }
        refreshTask = task
        defer { if authenticationGeneration == generation { refreshTask = nil } }
        return try await task.value
    }

    private func get(
        path: String,
        clientID: String,
        bearerToken: String
    ) async throws -> Data {
        let host = path.hasPrefix("/oauth/") ? "auth.trakt.tv" : "api.trakt.tv"
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw IntegrationError.message("The Trakt API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await browserTokenSession.data(for: request, delegate: AccountNoRedirectDelegate())
        guard let http = response as? HTTPURLResponse, data.count < 5_000_000 else {
            throw IntegrationError.message("Trakt returned an invalid network response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let responseText = String(data: data, encoding: .utf8) ?? ""
            throw TraktAPIError(statusCode: http.statusCode, responseText: responseText)
        }
        return data
    }

    private func post<Response: Decodable>(
        path: String,
        body: [String: Any],
        clientID: String,
        bearerToken: String?,
        acceptsPendingAuthorization: Bool
    ) async throws -> Response {
        let host = path.hasPrefix("/oauth/") ? "auth.trakt.tv" : "api.trakt.tv"
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw IntegrationError.message("The Trakt API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, response) = try await browserTokenSession.data(for: request, delegate: AccountNoRedirectDelegate())
        guard let http = response as? HTTPURLResponse, data.count < 5_000_000 else {
            throw IntegrationError.message("Trakt returned an invalid network response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if acceptsPendingAuthorization {
                let errorName = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                switch TraktOAuthPolicy.devicePollAction(status: http.statusCode, error: errorName) {
                case .pending: throw DeviceAuthorizationPendingError(slowDown: false)
                case .slowDown: throw DeviceAuthorizationPendingError(slowDown: true)
                case .denied: throw IntegrationError.message("Trakt sign-in was declined. You can try again when ready.")
                case .expired: throw IntegrationError.message("The sign-in code expired. Start sign-in again.")
                case .invalidCode: throw IntegrationError.message("Trakt did not recognize this code. Start sign-in again.")
                case .alreadyUsed: throw IntegrationError.message("This code has already been used. Start sign-in again.")
                case .failed: break
                }
            }
            throw TraktAPIError(statusCode: http.statusCode, responseText: "Try again later.")
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct EmptyResponse: Decodable {}

    private struct DeviceAuthorizationPendingError: Error {
        let slowDown: Bool
    }

    private enum IntegrationError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case let .message(message) = self { return message }
            return nil
        }
    }
}

private struct TraktTokenKeychain {
    private let service = "com.diam0ndnex.cinenex.trakt"
    private let account = "oauth-tokens"

    func load() throws -> TraktTokenResponse? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(TraktTokenResponse.self, from: data)
    }

    func save(_ token: TraktTokenResponse) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Could not securely store Trakt credentials (Keychain error \(status))."
        }
    }
}

enum TraktScrobbleMetadata {
    static func moviePayload(for item: MediaItem) -> [String: Any] {
        var movie: [String: Any] = [
            "title": item.title,
            "year": item.year
        ]
        if item.metadataProvider == "tmdb",
           let tmdbID = item.externalID,
           tmdbID > 0 {
            movie["ids"] = ["tmdb": tmdbID]
        }
        return movie
    }
}
