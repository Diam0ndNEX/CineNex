import XCTest
@testable import CineNex

final class TraktHistoryTests: XCTestCase {
    func testHistoryDecodeDeduplicatesMoviesAndKeepsLatestWatchDateAndPlayCount() throws {
        let data = Data("""
        [
          {"watched_at":"2026-10-20T12:00:00.000Z","plays":1,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},
          {"watched_at":"2026-10-22T12:00:00.000Z","plays":3,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},
          {"watched_at":"2026-10-21T12:00:00.000Z","plays":1,"movie":{"title":"Dune","year":2021,"ids":{"tmdb":438631}}},
          {"watched_at":"2026-10-21T12:00:00.000Z","movie":{"title":"   ","year":2020,"ids":{"tmdb":12}}}
        ]
        """.utf8)

        let movies = try TraktHistoryMovie.decodeList(data)

        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].title, "Arrival")
        XCTAssertEqual(movies[0].watchedAt, "2026-10-22T12:00:00.000Z")
        XCTAssertEqual(movies[0].playCount, 3)
        XCTAssertEqual(movies[1].title, "Dune")
    }

    func testHistoryDecodeRejectsInvalidJSON() {
        XCTAssertThrowsError(try TraktHistoryMovie.decodeList(Data("not-json".utf8)))
    }

    func testHistoryStoreMergesDuplicatesAndPersistsNewestWatchRecord() async throws {
        let suiteName = "TraktHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = await MainActor.run {
            TraktHistoryStore(defaults: defaults, storageKey: "history")
        }
        let earlier = try TraktHistoryMovie.decodeList(Data("""
        [{"watched_at":"2026-10-20T12:00:00.000Z","plays":1,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}}]
        """.utf8))
        let later = try TraktHistoryMovie.decodeList(Data("""
        [{"watched_at":"2026-10-22T12:00:00.000Z","plays":3,"movie":{"title":"Arrival","year":2016,"ids":{"tmdb":329865}}},{"watched_at":"2026-10-21T12:00:00.000Z","movie":{"title":"Dune","year":2021,"ids":{"tmdb":438631}}}]
        """.utf8))

        let firstAdded = await MainActor.run { store.importMovies(earlier) }
        let secondAdded = await MainActor.run { store.importMovies(later) }
        let saved = await MainActor.run { store.entries }
        let restored = await MainActor.run {
            TraktHistoryStore(defaults: defaults, storageKey: "history")
        }
        let restoredEntries = await MainActor.run { restored.entries }

        XCTAssertEqual(firstAdded, 1)
        XCTAssertEqual(secondAdded, 1)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first(where: { $0.id == "tmdb-movie-329865" })?.watchedAt, "2026-10-22T12:00:00.000Z")
        XCTAssertEqual(saved.first(where: { $0.id == "tmdb-movie-329865" })?.plays, 3)
        XCTAssertEqual(restoredEntries, saved)
    }
}
