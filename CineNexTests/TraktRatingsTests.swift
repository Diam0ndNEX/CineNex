import XCTest
@testable import CineNex

@MainActor
final class TraktRatingsTests: XCTestCase {
    func testRatingsDecodeDeduplicatesAndKeepsMostRecentlyRatedValue() throws {
        let data = Data("""
        [
          {"rated_at":"2026-10-20T12:00:00.000Z","rating":6,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},
          {"rated_at":"2026-10-22T12:00:00.000Z","rating":9,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},
          {"rated_at":"2026-10-21T12:00:00.000Z","rating":8,"movie":{"title":"Dune","year":2021,"ids":{"tmdb":438631}}},
          {"rated_at":"2026-10-23T12:00:00.000Z","rating":11,"movie":{"title":"Invalid score","year":2020,"ids":{"tmdb":12}}},
          {"rated_at":"2026-10-23T12:00:00.000Z","rating":7,"movie":{"title":"   ","year":2020,"ids":{"tmdb":13}}}
        ]
        """.utf8)

        let movies = try TraktRatingMovie.decodeList(data)

        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].title, "Arrival")
        XCTAssertEqual(movies[0].rating, 9)
        XCTAssertEqual(movies[0].ratedAt, "2026-10-22T12:00:00.000Z")
        XCTAssertEqual(movies[1].title, "Dune")
        XCTAssertEqual(movies[1].rating, 8)
    }

    func testRatingsDecodeRejectsInvalidJSON() {
        XCTAssertThrowsError(try TraktRatingMovie.decodeList(Data("not-json".utf8)))
    }

    func testRatingStoreMergesNewestRatingAndPersistsWithoutDuplicates() async throws {
        let suiteName = "TraktRatingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = await MainActor.run {
            TraktRatingStore(defaults: defaults, storageKey: "ratings")
        }
        let earlier = try TraktRatingMovie.decodeList(Data("""
        [{"rated_at":"2026-10-20T12:00:00.000Z","rating":6,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}}]
        """.utf8))
        let later = try TraktRatingMovie.decodeList(Data("""
        [{"rated_at":"2026-10-22T12:00:00.000Z","rating":9,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},{"rated_at":"2026-10-21T12:00:00.000Z","rating":8,"movie":{"title":"Dune","year":2021,"ids":{"tmdb":438631}}}]
        """.utf8))

        let firstAdded = await MainActor.run { store.importMovies(earlier) }
        let secondAdded = await MainActor.run { store.importMovies(later) }
        let saved = await MainActor.run { store.entries }
        let restored = await MainActor.run {
            TraktRatingStore(defaults: defaults, storageKey: "ratings")
        }
        let restoredEntries = await MainActor.run { restored.entries }

        XCTAssertEqual(firstAdded, 1)
        XCTAssertEqual(secondAdded, 1)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first(where: { $0.id == "tmdb-movie-329865" })?.rating, 9)
        XCTAssertEqual(saved.first(where: { $0.id == "tmdb-movie-329865" })?.ratedAt, "2026-10-22T12:00:00.000Z")
        XCTAssertEqual(restoredEntries, saved)
    }
}
