import XCTest
@testable import CineNex

@MainActor
final class TraktRatingsStoreRecoveryTests: XCTestCase {
    func testStoreRestoresLatestDuplicateAndDropsInvalidPersistedRatings() async throws {
        let suiteName = "TraktRatingsStoreRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let savedEntries = [
            TraktRatingEntry(
                id: "tmdb-movie-329865",
                title: " Arrival ",
                year: 2016,
                tmdbID: 329865,
                ratedAt: "2026-10-20T12:00:00.000Z",
                rating: 6
            ),
            TraktRatingEntry(
                id: "tmdb-movie-329865",
                title: "Arrival",
                year: 2016,
                tmdbID: 329865,
                ratedAt: "2026-10-22T12:00:00.000Z",
                rating: 9
            ),
            TraktRatingEntry(
                id: "blank-title",
                title: "   ",
                year: 2020,
                tmdbID: nil,
                ratedAt: "2026-10-23T12:00:00.000Z",
                rating: 8
            ),
            TraktRatingEntry(
                id: "invalid-score",
                title: "Invalid Score",
                year: 2020,
                tmdbID: nil,
                ratedAt: "2026-10-23T12:00:00.000Z",
                rating: 11
            ),
            TraktRatingEntry(
                id: "   ",
                title: "Invalid ID",
                year: 2020,
                tmdbID: nil,
                ratedAt: "2026-10-23T12:00:00.000Z",
                rating: 7
            )
        ]
        defaults.set(try JSONEncoder().encode(savedEntries), forKey: "ratings")

        let store = await MainActor.run {
            TraktRatingStore(defaults: defaults, storageKey: "ratings")
        }
        let restored = await MainActor.run { store.entries }

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, "tmdb-movie-329865")
        XCTAssertEqual(restored.first?.title, "Arrival")
        XCTAssertEqual(restored.first?.rating, 9)
        XCTAssertEqual(restored.first?.ratedAt, "2026-10-22T12:00:00.000Z")
    }

    func testStoreRestoresEmptyListForMalformedPersistedData() async {
        let suiteName = "TraktRatingsStoreRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "ratings")

        let store = await MainActor.run {
            TraktRatingStore(defaults: defaults, storageKey: "ratings")
        }
        let restored = await MainActor.run { store.entries }

        XCTAssertTrue(restored.isEmpty)
    }
}
