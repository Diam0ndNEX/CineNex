import XCTest
@testable import CineNex

final class MediaItemTests: XCTestCase {
    func testDemoCatalogContainsMoviesAndSeries() {
        let catalog = MediaItem.demoCatalog

        XCTAssertFalse(catalog.isEmpty)
        XCTAssertTrue(catalog.contains { $0.kind == .movie })
        XCTAssertTrue(catalog.contains { $0.kind == .series })
    }

    func testDemoCatalogIdentifiersAreUnique() {
        let identifiers = MediaItem.demoCatalog.map(\.id)

        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }

    func testPlayableSampleHasHTTPSURL() {
        let sample = MediaItem.demoCatalog.first { $0.id == "big-buck-bunny" }

        XCTAssertNotNil(sample?.streamURL)
        XCTAssertEqual(sample?.streamURL?.scheme, "https")
    }
}
