import XCTest
@testable import CineNex

final class PlaybackCleanerPolicyTests: XCTestCase {
    func testCleanerCanBeDisabledGloballyOrForOneProvider() {
        XCTAssertTrue(PlaybackCleanerPolicy.isEnabled(globallyEnabled: true, providerID: "vidsrc", disabledProviderIDs: []))
        XCTAssertFalse(PlaybackCleanerPolicy.isEnabled(globallyEnabled: false, providerID: "vidsrc", disabledProviderIDs: []))
        XCTAssertFalse(PlaybackCleanerPolicy.isEnabled(globallyEnabled: true, providerID: "vidsrc", disabledProviderIDs: ["vidsrc"]))
    }

    func testProviderExceptionsRoundTripAndIgnoreEmptyEntries() {
        let disabled = PlaybackCleanerPolicy.disabledProviderIDs(from: "vidsrc, ,two-embed,vidsrc")
        XCTAssertEqual(disabled, ["vidsrc", "two-embed"])
        XCTAssertEqual(PlaybackCleanerPolicy.disabledProviderIDs(from: PlaybackCleanerPolicy.storedValue(for: disabled)), disabled)
    }

    func testNavigationPolicyRejectsUnsafeSchemesAndCredentials() {
        XCTAssertFalse(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "http://player.example/movie")!, cleanerEnabled: false))
        XCTAssertFalse(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "https://user:password@player.example/movie")!, cleanerEnabled: false))
        XCTAssertFalse(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "javascript:alert(1)")!, cleanerEnabled: false))
    }

    func testNavigationPolicyBlocksKnownAdHostsAndSubdomainsOnlyWhenEnabled() {
        XCTAssertFalse(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "https://ads.doubleclick.net/redirect")!, cleanerEnabled: true))
        XCTAssertFalse(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "https://doubleclick.net/")!, cleanerEnabled: true))
        XCTAssertTrue(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "https://doubleclick.net/")!, cleanerEnabled: false))
        XCTAssertTrue(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "https://notdoubleclick.net/video")!, cleanerEnabled: true))
        XCTAssertTrue(PlaybackCleanerPolicy.shouldAllowNavigation(to: URL(string: "https://player.example/video")!, cleanerEnabled: true))
    }

    func testContentBlockerRulesAreValidJSONAndLimitBlockingToThirdPartyRequests() throws {
        let data = try XCTUnwrap(PlaybackCleanerPolicy.contentBlockerJSON().data(using: .utf8))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rules.count, 1)
        let trigger = try XCTUnwrap(rules[0]["trigger"] as? [String: Any])
        XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
        XCTAssertNotNil(trigger["url-filter"] as? String)
        let action = try XCTUnwrap(rules[0]["action"] as? [String: String])
        XCTAssertEqual(action["type"], "block")
    }
}
