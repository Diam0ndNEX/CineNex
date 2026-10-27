import XCTest
@testable import CineNex

final class HomeHeroPagingTests: XCTestCase {
    func testCatalogRefreshKeepsCurrentTitleWhenItsPositionChanges() {
        XCTAssertEqual(HomeHeroPaging.reconciledID("second", in: ["third", "second", "first"]), "second")
        XCTAssertEqual(HomeHeroPaging.reconciledID("removed", in: ["new", "other"]), "new")
        XCTAssertEqual(HomeHeroPaging.reconciledID("old", in: []), "")
    }

    func testManualAdvancementWrapsInBothDirections() {
        let ids = ["first", "second", "third"]
        XCTAssertEqual(HomeHeroPaging.adjacentID(to: "first", in: ids, forward: true), "second")
        XCTAssertEqual(HomeHeroPaging.adjacentID(to: "third", in: ids, forward: true), "first")
        XCTAssertEqual(HomeHeroPaging.adjacentID(to: "first", in: ids, forward: false), "third")
    }

    func testNoTitlesAndOneTitleDoNotCreateInvalidPages() {
        XCTAssertNil(HomeHeroPaging.adjacentID(to: "old", in: [], forward: true))
        XCTAssertEqual(HomeHeroPaging.adjacentID(to: "only", in: ["only"], forward: false), "only")
        XCTAssertEqual(HomeHeroPaging.adjacentID(to: "stale", in: ["new", "next"], forward: true), "next")
    }
    func testResumeLabelsRejectInvalidAndExtremeMetadataWithoutIntegerOverflow() {
        XCTAssertEqual(HomeResumeProgress.label(position: 61, duration: 180), "2 min remaining")
        XCTAssertEqual(HomeResumeProgress.label(position: 125, duration: 0), "2 min watched")
        XCTAssertEqual(HomeResumeProgress.label(position: 181, duration: 180), "Almost finished")
        XCTAssertEqual(HomeResumeProgress.label(position: -.infinity, duration: 100), "Ready to resume")
        XCTAssertEqual(HomeResumeProgress.label(position: -1, duration: 100), "Ready to resume")
        XCTAssertEqual(HomeResumeProgress.label(position: 0, duration: .greatestFiniteMagnitude), "Ready to resume")
        XCTAssertEqual(HomeResumeProgress.label(position: .greatestFiniteMagnitude, duration: 0), "Ready to resume")
    }

}
