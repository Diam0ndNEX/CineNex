import AuthenticationServices
import Combine
import Foundation
import Security
import UIKit

enum AccountAuthError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

enum AnimeAccountProvider: String, CaseIterable, Identifiable, Codable {
    case aniList, myAnimeList
    var id: String { rawValue }
    var title: String { self == .aniList ? "AniList" : "MyAnimeList" }
    var clientID: String {
        let key = self == .aniList ? "CINENEX_ANILIST_CLIENT_ID" : "CINENEX_MAL_CLIENT_ID"
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value
    }
    var redirect: URL { URL(string: "cinenex://oauth/\(rawValue)")! }
}

struct AnimeAccountListEntry: Identifiable, Sendable {
    let id: Int
    let title: String
    let watchedEpisodes: Int
    let status: String
}

private struct AnimeOAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

enum AnimeOAuthPolicy {
    static func randomVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AccountAuthError.message("Secure sign-in could not be prepared.")
        }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func callbackValues(_ callback: URL, expected: URL, state: String) throws -> [String: String] {
        guard callback.scheme == expected.scheme, callback.host == expected.host, callback.path == expected.path, callback.port == expected.port, callback.user == nil, callback.password == nil else {
            throw AccountAuthError.message("The sign-in redirect did not match CineNex.")
        }
        let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let fragment = parts?.fragment.flatMap { URLComponents(string: "https://callback.invalid/?" + $0)?.queryItems } ?? []
        var values: [String: String] = [:]
        for item in (parts?.queryItems ?? []) + fragment {
            guard values[item.name] == nil else { throw AccountAuthError.message("The sign-in response contained duplicate parameters.") }
            values[item.name] = item.value ?? ""
        }
        guard values["state"] == state, !state.isEmpty else { throw AccountAuthError.message("The sign-in security check failed.") }
        guard values["error"] == nil else { throw AccountAuthError.message("Authorization was declined. You can try signing in again.") }
        return values
    }
}

@MainActor
final class AnimeWebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func authorize(_ url: URL, callback expected: URL = URL(string: "cinenex://oauth/aniList")!) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let match: ASWebAuthenticationSession.Callback
            if expected.scheme == "https", let host = expected.host {
                match = .https(host: host, path: expected.path)
            } else {
                match = .customScheme(expected.scheme ?? "cinenex")
            }
            let session = ASWebAuthenticationSession(url: url, callback: match) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? AccountAuthError.message("Sign-in did not finish.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else { continuation.resume(throwing: AccountAuthError.message("The sign-in browser could not open.")); return }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

@MainActor
final class AnimeAccountIntegration: ObservableObject {
    @Published private(set) var userName: String?
    @Published private(set) var entries: [AnimeAccountListEntry] = []
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    let provider: AnimeAccountProvider
    private let login = AnimeWebLogin()
    private let accountSession = URLSession(configuration: .ephemeral)
    private var keychain: KeychainStringStore { KeychainStringStore(service: "com.diam0ndnex.cinenex.accounts", account: provider.rawValue) }
    var hasSavedSession: Bool { (try? keychain.load()) != nil }
    var isConfigured: Bool { !provider.clientID.isEmpty }

    init(provider: AnimeAccountProvider) { self.provider = provider }

    func signIn() async {
        guard !isWorking else { return }
        guard isConfigured else { message = "Account login is not enabled in this build. The CineNex developer must register this service once; you do not need an API key."; return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let state = try AnimeOAuthPolicy.randomVerifier()
            let verifier = try AnimeOAuthPolicy.randomVerifier()
            var url = URLComponents(string: provider == .aniList ? "https://anilist.co/api/v2/oauth/authorize" : "https://myanimelist.net/v1/oauth2/authorize")!
            url.queryItems = [URLQueryItem(name: "client_id", value: provider.clientID),
                              URLQueryItem(name: "redirect_uri", value: provider.redirect.absoluteString),
                              URLQueryItem(name: "response_type", value: provider == .aniList ? "token" : "code"),
                              URLQueryItem(name: "state", value: state)]
            if provider == .myAnimeList {
                url.queryItems? += [URLQueryItem(name: "code_challenge", value: verifier), URLQueryItem(name: "code_challenge_method", value: "plain")]
            }
            guard let authorizeURL = url.url else { throw AccountAuthError.message("Could not prepare sign-in.") }
            let callback = try await login.authorize(authorizeURL, callback: provider.redirect)
            let values = try AnimeOAuthPolicy.callbackValues(callback, expected: provider.redirect, state: state)
            let token: AnimeOAuthToken
            if provider == .aniList {
                guard let access = values["access_token"], !access.isEmpty else { throw AccountAuthError.message("AniList did not return an access token.") }
                token = AnimeOAuthToken(accessToken: access, refreshToken: nil, expiresAt: Date().addingTimeInterval(Double(values["expires_in"] ?? "") ?? 31_536_000))
            } else {
                guard let code = values["code"], !code.isEmpty else { throw AccountAuthError.message("MyAnimeList did not return an authorization code.") }
                token = try await malToken(["client_id": provider.clientID, "grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": provider.redirect.absoluteString])
            }
            try save(token)
            try await loadAccount(token)
        } catch { message = "Sign-in could not finish. \(error.localizedDescription)" }
    }

    func refresh() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let stored = try keychain.load(), let data = stored.data(using: .utf8) else { return }
            var token = try JSONDecoder().decode(AnimeOAuthToken.self, from: data)
            if token.expiresAt <= Date() {
                guard provider == .myAnimeList, isConfigured, let refresh = token.refreshToken else { throw AccountAuthError.message("Your session expired. Sign out and sign in again.") }
                token = try await malToken(["client_id": provider.clientID, "grant_type": "refresh_token", "refresh_token": refresh])
                try save(token)
            }
            try await loadAccount(token)
        } catch { message = error.localizedDescription }
    }

    func disconnect() {
        do { try keychain.delete(); userName = nil; entries = []; message = "Disconnected on this device." }
        catch { message = "The saved session could not be removed. Try again." }
    }

    private func save(_ token: AnimeOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        guard let text = String(data: data, encoding: .utf8) else { throw AccountAuthError.message("Could not save the session.") }
        try keychain.save(text)
    }

    private func malToken(_ fields: [String: String]) async throws -> AnimeOAuthToken {
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents(); body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let object = try await json(request)
        guard let access = object["access_token"] as? String, !access.isEmpty,
              let seconds = object["expires_in"] as? Double, seconds > 0 else { throw AccountAuthError.message("MyAnimeList returned an invalid token response.") }
        return AnimeOAuthToken(accessToken: access, refreshToken: object["refresh_token"] as? String, expiresAt: Date().addingTimeInterval(seconds))
    }

    private func loadAccount(_ token: AnimeOAuthToken) async throws {
        if provider == .aniList {
            let profile = try await aniList(query: "query { Viewer { id name } }", token: token.accessToken)
            guard let viewer = (profile["data"] as? [String: Any])?["Viewer"] as? [String: Any],
                  let id = viewer["id"] as? Int, let name = viewer["name"] as? String else { throw AccountAuthError.message("AniList could not confirm your account.") }
            userName = name
            let list = try await aniList(query: "query { MediaListCollection(userId: \(id), type: ANIME) { lists { entries { mediaId progress status media { title { userPreferred } } } } } }", token: token.accessToken)
            let collection = (list["data"] as? [String: Any])?["MediaListCollection"] as? [String: Any]
            let lists = collection?["lists"] as? [[String: Any]] ?? []
            var seen = Set<Int>()
            entries = lists.flatMap { $0["entries"] as? [[String: Any]] ?? [] }.compactMap { entry in
                guard let id = entry["mediaId"] as? Int, seen.insert(id).inserted,
                      let media = entry["media"] as? [String: Any], let title = media["title"] as? [String: Any], let name = title["userPreferred"] as? String else { return nil }
                return AnimeAccountListEntry(id: id, title: name, watchedEpisodes: entry["progress"] as? Int ?? 0, status: entry["status"] as? String ?? "")
            }
        } else {
            var profileRequest = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/users/@me")!)
            profileRequest.setValue("Bearer " + token.accessToken, forHTTPHeaderField: "Authorization")
            let profile = try await json(profileRequest)
            guard let name = profile["name"] as? String else { throw AccountAuthError.message("MyAnimeList could not confirm your account.") }
            userName = name
            var listRequest = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/users/@me/animelist?fields=list_status&limit=100")!)
            listRequest.setValue("Bearer " + token.accessToken, forHTTPHeaderField: "Authorization")
            let list = try await json(listRequest)
            entries = (list["data"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let node = entry["node"] as? [String: Any], let id = node["id"] as? Int, let title = node["title"] as? String else { return nil }
                let status = entry["list_status"] as? [String: Any] ?? [:]
                return AnimeAccountListEntry(id: id, title: title, watchedEpisodes: status["num_episodes_watched"] as? Int ?? 0, status: status["status"] as? String ?? "")
            }
        }
        message = provider == .myAnimeList ? "Loaded the first 100 list entries. This is a read-only account list." : "Account list loaded. This is read-only; local episode tracking is separate."
    }

    private func aniList(query: String, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let object = try await json(request)
        guard object["errors"] == nil else { throw AccountAuthError.message("AniList could not load this account data.") }
        return object
    }

    private func json(_ input: URLRequest) async throws -> [String: Any] {
        var request = input; request.timeoutInterval = 20
        let (data, response) = try await accountSession.data(for: request, delegate: AccountNoRedirectDelegate())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 5_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AccountAuthError.message("The account service rejected the request. Try signing in again.") }
        return object
    }
}

/// Stateless delegate: credential-bearing API requests must never follow redirects.
final class AccountNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
