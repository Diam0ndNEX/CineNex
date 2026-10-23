import Combine
import Foundation
import Security

struct TraktDeviceAuthorization: Decodable, Equatable {
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

private struct TraktTokenResponse: Codable {
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
    @Published private(set) var activeAuthorization: TraktDeviceAuthorization?

    private let defaults: UserDefaults
    private let clientIDKey = "cinenex.trakt.clientID"
    private let tokenStore = TraktTokenKeychain()
    private var tokens: TraktTokenResponse?

    var savedClientID: String {
        defaults.string(forKey: clientIDKey) ?? ""
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.tokens = try? tokenStore.load()
        self.isConnected = tokens != nil
        self.statusMessage = tokens == nil ? "Not connected" : "Trakt account connected"
    }

    func saveClientID(_ clientID: String) {
        defaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey)
        lastError = nil
    }

    func requestDeviceAuthorization(clientID: String) async throws -> TraktDeviceAuthorization {
        let normalizedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw IntegrationError.message("Enter the Client ID from your Trakt API application first.")
        }
        saveClientID(normalizedID)
        statusMessage = "Requesting a sign-in code…"
        lastError = nil

        let authorization = try await post(
            path: "/oauth/device/code",
            body: ["client_id": normalizedID],
            clientID: normalizedID,
            bearerToken: nil,
            acceptsPendingAuthorization: false
        ) as TraktDeviceAuthorization

        activeAuthorization = authorization
        statusMessage = "Enter the code on Trakt to authorize CineNex."
        return authorization
    }

    func completeDeviceAuthorization(_ authorization: TraktDeviceAuthorization) async {
        let clientID = savedClientID
        var delay = max(authorization.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(authorization.expiresIn))
        statusMessage = "Waiting for Trakt authorization…"
        lastError = nil

        while !Task.isCancelled && Date() < deadline {
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                let token: TraktTokenResponse = try await post(
                    path: "/oauth/device/token",
                    body: [
                        "code": authorization.deviceCode,
                        "client_id": clientID
                    ],
                    clientID: clientID,
                    bearerToken: nil,
                    acceptsPendingAuthorization: true
                )
                try tokenStore.save(token)
                tokens = token
                isConnected = true
                activeAuthorization = nil
                statusMessage = "Trakt account connected"
                lastError = nil
                return
            } catch let error as DeviceAuthorizationPendingError {
                if error.slowDown {
                    delay += 5
                }
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Trakt connection failed"
                activeAuthorization = nil
                return
            }
        }

        if !Task.isCancelled {
            lastError = "The sign-in code expired. Start the connection again to get a new code."
            statusMessage = "Authorization expired"
            activeAuthorization = nil
        }
    }

    func reportSetupError(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = "Trakt connection failed"
    }

    func disconnect() {
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

        let refreshed: TraktTokenResponse = try await post(
            path: "/oauth/token",
            body: [
                "refresh_token": current.refreshToken,
                "client_id": savedClientID,
                "grant_type": "refresh_token"
            ],
            clientID: savedClientID,
            bearerToken: nil,
            acceptsPendingAuthorization: false
        )
        try tokenStore.save(refreshed)
        tokens = refreshed
        return refreshed
    }

    private func get(
        path: String,
        clientID: String,
        bearerToken: String
    ) async throws -> Data {
        guard let url = URL(string: "https://api.trakt.tv\(path)") else {
            throw IntegrationError.message("The Trakt API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
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
        guard let url = URL(string: "https://api.trakt.tv\(path)") else {
            throw IntegrationError.message("The Trakt API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IntegrationError.message("Trakt returned an invalid network response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let responseText = String(data: data, encoding: .utf8) ?? ""
            if acceptsPendingAuthorization, http.statusCode == 400 {
                let errorName = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                if errorName == "authorization_pending" {
                    throw DeviceAuthorizationPendingError(slowDown: false)
                }
                if errorName == "slow_down" {
                    throw DeviceAuthorizationPendingError(slowDown: true)
                }
            }
            throw TraktAPIError(statusCode: http.statusCode, responseText: responseText)
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
