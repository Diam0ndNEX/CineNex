import XCTest
@testable import CineNex

final class EpisodeNavigatorPolicyTests: XCTestCase {
    private func episode(_ number: Int, title: String = "Episode", overview: String? = nil,
                         date: String? = nil, rating: Double? = nil) -> TMDBSeasonEpisode {
        TMDBSeasonEpisode(id: number, name: title, overview: overview, airDate: date,
                          episodeNumber: number, seasonNumber: 1, stillPath: nil, voteAverage: rating, runtime: nil)
    }

    func testSearchIncludesEpisodeNumberTitleAndOverview() {
        let episodes = [episode(1, title: "Arrival"), episode(2, title: "Signals", overview: "A hidden moon base"), episode(3, title: "Moonrise")]
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "02", sort: .firstToLast).map(\.episodeNumber), [2])
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: " MOON ", sort: .firstToLast).map(\.episodeNumber), [2, 3])
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "arrival", sort: .firstToLast).map(\.episodeNumber), [1])
    }

    func testSortsByActualMetadataAndDoesNotTreatFutureDatesAsNewestAired() {
        let episodes = [episode(3, date: "2027-01-01", rating: .nan), episode(2, date: "2026-10-01", rating: 8.5),
                        episode(1, date: "2024-01-01", rating: 9), episode(4, rating: 0)]
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "", sort: .newestAired, today: "2026-10-27").map(\.episodeNumber), [2, 1, 3, 4])
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "", sort: .lastToFirst).map(\.episodeNumber), [4, 3, 2, 1])
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "", sort: .highestRated).map(\.episodeNumber), [1, 2, 3, 4])
    }

    func testUnwatchedFiltersAndNextEpisodeUseExactLocalMarks() {
        let episodes = [episode(1), episode(2, date: "2026-10-01"), episode(3, date: "2027-01-01"), episode(4)]
        XCTAssertEqual(EpisodeNavigatorPolicy.nextUnwatched(episodes, watched: [1], today: "2026-10-27")?.episodeNumber, 2)
        XCTAssertEqual(EpisodeNavigatorPolicy.nextUnwatched(episodes, watched: [1, 2], today: "2026-10-27")?.episodeNumber, 4)
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "", sort: .unwatchedFirst, watched: [1, 3]).map(\.episodeNumber), [2, 4, 1, 3])
        XCTAssertEqual(EpisodeNavigatorPolicy.filtered(episodes, query: "", sort: .firstToLast, filter: .watched, watched: [2]).map(\.episodeNumber), [2])
    }

    func testDatesAndRatingsRejectInvalidMetadata() {
        XCTAssertEqual(EpisodeNavigatorPolicy.validDate("2024-02-29"), "2024-02-29")
        for invalid in ["2023-02-29", "2026-13-01", "2026-04-31", "2026-1-01", "0000-01-01", "tomorrow"] {
            XCTAssertNil(EpisodeNavigatorPolicy.validDate(invalid))
        }
        XCTAssertNil(EpisodeNavigatorPolicy.validRating(.infinity))
        XCTAssertNil(EpisodeNavigatorPolicy.validRating(11))
        XCTAssertNil(EpisodeNavigatorPolicy.validRating(0))
    }

    @MainActor
    func testManualMarksPersistWithoutConflatingShowsOrSeasons() throws {
        let suiteName = "EpisodeNavigatorPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let history = EpisodeNavigatorHistory(defaults: defaults)
        history.setWatched(true, itemID: "series:one", season: 1, episode: 2)
        history.setWatched(true, itemID: "series:one", season: 2, episode: 3)
        history.setWatched(true, itemID: "series:two", season: 1, episode: 4)
        history.setWatched(true, itemID: "", season: 1, episode: 1)
        let restored = EpisodeNavigatorHistory(defaults: defaults)
        XCTAssertEqual(restored.numbers(itemID: "series:one", season: 1), [2])
        XCTAssertEqual(restored.numbers(itemID: "series:one", season: 2), [3])
        XCTAssertEqual(restored.numbers(itemID: "series:two", season: 1), [4])
        XCTAssertEqual(restored.watched.count, 3)
        restored.setWatched(false, itemID: "series:one", season: 1, episode: 2)
        XCTAssertTrue(EpisodeNavigatorHistory(defaults: defaults).numbers(itemID: "series:one", season: 1).isEmpty)
    }
}
