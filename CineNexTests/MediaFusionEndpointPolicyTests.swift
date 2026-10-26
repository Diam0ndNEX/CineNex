import XCTest
@testable import CineNex

final class MediaFusionEndpointPolicyTests: XCTestCase {
    func testLegacyElfHostedOnlyConfigurationAlsoQueriesMidnight() throws {
        let elfHosted = try XCTUnwrap(URL(string: "https://mediafusion.elfhosted.com/manifest.json"))
        let endpoints = MediaFusionEndpointPolicy.withFallbacks([elfHosted])
        XCTAssertTrue(endpoints.contains { $0.host == "mediafusionfortheweebs.midnightignite.me" })
        XCTAssertTrue(endpoints.contains(elfHosted))
        XCTAssertEqual(Set(endpoints).count, endpoints.count)
    }

    func testConfiguredPrivateMediaFusionPathIsPreservedWithoutExtraInstances() throws {
        let configured = try XCTUnwrap(URL(string: "https://mediafusion.example/settings/manifest.json"))
        XCTAssertEqual(MediaFusionEndpointPolicy.withFallbacks([configured]), [configured])
    }

    func testDefaultEndpointsAreNotDuplicated() throws {
        let endpoints = try [
            "https://mediafusion.elfhosted.com/manifest.json",
            "https://mediafusionfortheweebs.midnightignite.me/manifest.json"
        ].map { try XCTUnwrap(URL(string: $0)) }
        XCTAssertEqual(MediaFusionEndpointPolicy.withFallbacks(endpoints), endpoints)
    }
}
