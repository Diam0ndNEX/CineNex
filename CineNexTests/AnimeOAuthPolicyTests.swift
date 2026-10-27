import XCTest
@testable import CineNex

final class AnimeOAuthPolicyTests: XCTestCase {
    func testVerifierHasRequiredEntropyLengthAndURLSafeAlphabet() throws {
        let first = try AnimeOAuthPolicy.randomVerifier()
        let second = try AnimeOAuthPolicy.randomVerifier()
        XCTAssertEqual(first.count, 43)
        XCTAssertNotEqual(first, second)
        XCTAssertNotNil(first.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
    }
    func testCallbackRejectsWrongStateAndRedirectIdentity() throws {
        let expected = URL(string: "cinenex://oauth/aniList")!
        XCTAssertThrowsError(try AnimeOAuthPolicy.callbackValues(URL(string: "cinenex://oauth/aniList#state=wrong&access_token=fixture")!, expected: expected, state: "right"))
        XCTAssertThrowsError(try AnimeOAuthPolicy.callbackValues(URL(string: "cinenex://attacker/aniList#state=right")!, expected: expected, state: "right"))
        XCTAssertThrowsError(try AnimeOAuthPolicy.callbackValues(URL(string: "cinenex://oauth/aniList?state=right#state=right")!, expected: expected, state: "right"))
        XCTAssertThrowsError(try AnimeOAuthPolicy.callbackValues(URL(string: "cinenex://oauth/aniList?state=right&error=access_denied")!, expected: expected, state: "right"))
    }
    func testCallbackAcceptsTokenFragmentAndAuthorizationCodeQuery() throws {
        let expected = URL(string: "cinenex://oauth/aniList")!
        let fragment = try AnimeOAuthPolicy.callbackValues(URL(string: "cinenex://oauth/aniList#state=fixture&access_token=example")!, expected: expected, state: "fixture")
        XCTAssertEqual(fragment["access_token"], "example")
        let query = try AnimeOAuthPolicy.callbackValues(URL(string: "cinenex://oauth/aniList?state=fixture&code=example")!, expected: expected, state: "fixture")
        XCTAssertEqual(query["code"], "example")
    }
}
