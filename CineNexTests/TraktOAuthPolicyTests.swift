import XCTest
@testable import CineNex

final class TraktOAuthPolicyTests: XCTestCase {
    func testS256MatchesRFC7636AppendixB() {
        XCTAssertEqual(TraktOAuthPolicy.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testTraktAuthorizationRequiresHTTPSAndSendsFreshPKCEInsteadOfSecret() throws {
        let redirect = try XCTUnwrap(TraktOAuthPolicy.validRedirect("https://login.example.test/callback/trakt"))
        XCTAssertNil(TraktOAuthPolicy.validRedirect("cinenex://oauth/trakt"))
        XCTAssertNil(TraktOAuthPolicy.validRedirect("http://example.test/callback"))
        XCTAssertNil(TraktOAuthPolicy.validRedirect("https://user:secret@example.test/callback"))
        let url = try TraktOAuthPolicy.authorizationURL(clientID: "fixture", redirect: redirect,
                                                         verifier: String(repeating: "a", count: 43), state: "random-state")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "auth.trakt.tv")
        XCTAssertEqual(query.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(query.first { $0.name == "redirect_uri" }?.value, redirect.absoluteString)
        XCTAssertNil(query.first { $0.name == "client_secret" })
    }
    func testTokenExchangeAndRefreshUseAuthHostWithoutClientSecret() throws {
        let request = try TraktOAuthPolicy.tokenRequest(["grant_type": "authorization_code", "code": "fixture-code",
                                                        "code_verifier": String(repeating: "a", count: 43),
                                                        "redirect_uri": "https://login.example.test/callback/trakt"], clientID: "fixture")
        XCTAssertEqual(request.url?.absoluteString, "https://auth.trakt.tv/oauth/token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["client_id"], "fixture")
        XCTAssertNotNil(body["code_verifier"])
        XCTAssertNil(body["client_secret"])
        XCTAssertThrowsError(try TraktOAuthPolicy.tokenRequest(["grant_type": "authorization_code", "code": "fixture"], clientID: "fixture"))
        XCTAssertThrowsError(try TraktOAuthPolicy.tokenRequest(["grant_type": "refresh_token", "refresh_token": "fixture", "client_secret": "forbidden"], clientID: "fixture"))
        let refresh = try TraktOAuthPolicy.tokenRequest(["grant_type": "refresh_token", "refresh_token": "fixture"], clientID: "fixture")
        XCTAssertEqual(refresh.url?.host, "auth.trakt.tv")
    }
}
