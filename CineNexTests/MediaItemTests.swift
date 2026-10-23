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
        XCTAssertEqual(sample?.streamURL?.host, "storage.googleapis.com")
    }

    func testCatalogItemsHaveNonemptyDisplayMetadata() {
        for item in MediaItem.demoCatalog {
            XCTAssertFalse(item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(item.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(item.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testNonPlayableDemoItemsDoNotClaimToHaveStreams() {
        let unavailableItems = MediaItem.demoCatalog.filter { $0.id != "big-buck-bunny" }

        XCTAssertFalse(unavailableItems.isEmpty)
        XCTAssertTrue(unavailableItems.allSatisfy { $0.streamURL == nil })
    }
}
