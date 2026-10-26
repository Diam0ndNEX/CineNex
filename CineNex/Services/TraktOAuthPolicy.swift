import CryptoKit
import Foundation

enum TraktOAuthPolicy {
    static func validRedirect(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
              !host.isEmpty, host != "localhost", host != "127.0.0.1", host != "[::1]",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil, !url.path.isEmpty else { return nil }
        return url
    }
    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func authorizationURL(clientID: String, redirect: URL, verifier: String, state: String) throws -> URL {
        guard !clientID.isEmpty, validRedirect(redirect.absoluteString) != nil, !state.isEmpty,
              verifier.range(of: "^[A-Za-z0-9._~-]{43,128}$", options: .regularExpression) != nil else {
            throw AccountAuthError.message("Trakt sign-in configuration is incomplete.")
        }
        var url = URLComponents(string: "https://auth.trakt.tv/oauth/authorize")!
        url.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
                          URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "state", value: state),
                          URLQueryItem(name: "code_challenge", value: challenge(verifier)), URLQueryItem(name: "code_challenge_method", value: "S256")]
        guard let result = url.url else { throw AccountAuthError.message("Trakt sign-in could not be prepared.") }
        return result
    }
    static func tokenRequest(_ fields: [String: String], clientID: String) throws -> URLRequest {
        let allowed: Set<String> = ["grant_type", "code", "code_verifier", "redirect_uri", "refresh_token"]
        guard !clientID.isEmpty, Set(fields.keys).isSubset(of: allowed) else { throw AccountAuthError.message("Trakt token request is invalid.") }
        switch fields["grant_type"] {
        case "authorization_code":
            guard let redirect = fields["redirect_uri"], validRedirect(redirect) != nil,
                  !(fields["code"] ?? "").isEmpty,
                  let verifier = fields["code_verifier"], verifier.range(of: "^[A-Za-z0-9._~-]{43,128}$", options: .regularExpression) != nil else {
                throw AccountAuthError.message("Trakt authorization response is incomplete.")
            }
        case "refresh_token":
            guard !(fields["refresh_token"] ?? "").isEmpty else { throw AccountAuthError.message("Your Trakt session needs sign-in again.") }
        default: throw AccountAuthError.message("Trakt token grant is invalid.")
        }
        var body = fields; body["client_id"] = clientID
        var request = URLRequest(url: URL(string: "https://auth.trakt.tv/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
