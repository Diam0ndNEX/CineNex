import XCTest
@testable import CineNex

final class TraktWatchlistTests: XCTestCase {
    func testWatchlistDecodeMapsMovieMetadataAndDeduplicatesEntries() throws {
        let data = Data("""
        [
          {"listed_at":"2026-10-20T12:00:00.000Z","movie":{"title":"Arrival","year":2016,"ids":{"trakt":1,"slug":"arrival-2016","tmdb":329865}}},
          {"listed_at":"2026-10-21T12:00:00.000Z","movie":{"title":"Arrival duplicate","year":2016,"ids":{"tmdb":329865}}},
          {"movie":{"title":"Interstellar","year":2014,"ids":{"tmdb":157336}}},
          {"movie":{"title":"   ","year":2020,"ids":{"tmdb":12}}}
        ]
        """.utf8)

        let movies = try TraktWatchlistMovie.decodeList(data)

        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].title, "Arrival")
        XCTAssertEqual(movies[0].year, 2016)
        XCTAssertEqual(movies[0].tmdbID, 329865)
        XCTAssertEqual(movies[1].title, "Interstellar")
        XCTAssertEqual(movies[1].id, "tmdb-movie-157336")
    }

    func testWatchlistDecodeRejectsInvalidJSON() {
        XCTAssertThrowsError(try TraktWatchlistMovie.decodeList(Data("not-json".utf8)))
    }

    func testWatchlistStoreMergesAndPersistsWithoutDuplicates() async throws {
        let suiteName = "TraktWatchlistTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = await MainActor.run {
            TraktWatchlistStore(defaults: defaults, storageKey: "watchlist")
        }
        let first = try TraktWatchlistMovie.decodeList(Data("""
        [{"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}}]
        """.utf8))
        let second = try TraktWatchlistMovie.decodeList(Data("""
        [{"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},{"movie":{"title":"Dune","year":2021,"ids":{"tmdb":438631}}}]
        """.utf8))

        let firstAdded = await MainActor.run { store.importMovies(first) }
        let secondAdded = await MainActor.run { store.importMovies(second) }
        let savedEntries = await MainActor.run { store.entries }
        let reloaded = await MainActor.run {
            TraktWatchlistStore(defaults: defaults, storageKey: "watchlist")
        }
        let reloadedEntries = await MainActor.run { reloaded.entries }

        XCTAssertEqual(firstAdded, 1)
        XCTAssertEqual(secondAdded, 1)
        XCTAssertEqual(savedEntries.count, 2)
        XCTAssertEqual(Set(savedEntries.map(\.id)).count, 2)
        XCTAssertEqual(reloadedEntries, savedEntries)
    }
}
