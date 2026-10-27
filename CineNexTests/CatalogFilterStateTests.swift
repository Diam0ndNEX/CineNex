import XCTest
@testable import CineNex

final class CatalogFilterStateTests: XCTestCase {
    private func item(year: Int = 2024, genre: String = "Action · Drama", rating: Double? = 8, poster: Bool = true) -> MediaItem {
        var item = MediaItem(id: "fixture", title: "A New Story", kind: .movie, year: year, genre: genre,
                             synopsis: "", symbol: "film", runtime: "", streamURL: nil)
        item.rating = rating
        item.posterURL = poster ? URL(string: "https://images.example.test/poster.jpg") : nil
        return item
    }

    func testExplicitMetadataBoundsRejectUnknownValues() {
        var filter = CatalogFilterState()
        XCTAssertTrue(filter.matches(item(year: 0, rating: nil, poster: false)))
        filter.earliestYear = 2020
        filter.latestYear = 2025
        filter.minimumRating = 7
        XCTAssertTrue(filter.matches(item(year: 2020, rating: 7)))
        XCTAssertTrue(filter.matches(item(year: 2025, rating: 9)))
        XCTAssertFalse(filter.matches(item(year: 0)))
        XCTAssertFalse(filter.matches(item(year: 2026)))
        XCTAssertFalse(filter.matches(item(rating: nil)))
        XCTAssertFalse(filter.matches(item(rating: 6.9)))
    }

    func testGenreUsesTokensRatherThanSubstringAndQueryTrimsWhitespace() {
        var filter = CatalogFilterState()
        filter.genre = "Action"
        filter.query = "  new STORY  "
        XCTAssertTrue(filter.matches(item()))
        XCTAssertFalse(filter.matches(item(genre: "Live Action")))
        filter.kind = "series"
        XCTAssertFalse(filter.matches(item()))
    }

    func testArtworkAndUnratedFiltersAreIndependentAndResettable() {
        var filter = CatalogFilterState()
        filter.hideUnrated = true
        filter.requirePoster = true
        XCTAssertEqual(filter.activeCount, 2)
        XCTAssertFalse(filter.matches(item(rating: nil)))
        XCTAssertFalse(filter.matches(item(poster: false)))
        XCTAssertTrue(filter.matches(item()))
        filter = CatalogFilterState()
        XCTAssertEqual(filter.activeCount, 0)
        XCTAssertTrue(filter.matches(item(rating: nil, poster: false)))
    }
}
