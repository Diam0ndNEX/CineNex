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
    func testDevicePollingSupportsDocumentedEmptyPendingAndSlowDownResponses() {
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 400, error: nil), .pending)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 400, error: "authorization_pending"), .pending)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 429, error: nil), .slowDown)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 400, error: "slow_down"), .slowDown)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 418, error: nil), .denied)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 410, error: nil), .expired)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 404, error: nil), .invalidCode)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 409, error: nil), .alreadyUsed)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 400, error: "invalid_client"), .failed)
        XCTAssertEqual(TraktOAuthPolicy.devicePollAction(status: 500, error: nil), .failed)
    }

    func testDeviceLoginRejectsUntrustedActivationAddressesAndInvalidLifetimes() throws {
        func authorization(_ url: String, expires: Int = 600, interval: Int = 5) throws -> TraktDeviceAuthorization {
            TraktDeviceAuthorization(deviceCode: "fixture-device", userCode: "ABC12345",
                                     verificationURL: try XCTUnwrap(URL(string: url)), expiresIn: expires, interval: interval)
        }
        XCTAssertTrue(TraktOAuthPolicy.validDeviceAuthorization(try authorization("https://auth.trakt.tv/activate")))
        XCTAssertTrue(TraktOAuthPolicy.validDeviceAuthorization(try authorization("https://trakt.tv/activate")))
        for address in ["http://auth.trakt.tv/activate", "https://trakt.tv.attacker.test/activate",
                        "https://user@auth.trakt.tv/activate", "https://auth.trakt.tv/activate?redirect=evil",
                        "https://auth.trakt.tv/other", "https://auth.trakt.tv:8443/activate"] {
            XCTAssertFalse(TraktOAuthPolicy.validDeviceAuthorization(try authorization(address)), address)
        }
        XCTAssertFalse(TraktOAuthPolicy.validDeviceAuthorization(try authorization("https://auth.trakt.tv/activate", expires: 0)))
        XCTAssertFalse(TraktOAuthPolicy.validDeviceAuthorization(try authorization("https://auth.trakt.tv/activate", interval: 0)))
    }

}
