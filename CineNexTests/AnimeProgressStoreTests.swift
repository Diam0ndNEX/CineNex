import XCTest
@testable import CineNex

@MainActor
final class AnimeProgressStoreTests: XCTestCase {
    func testProgressPersistsAndClampsToEpisodeCount() throws {
        let suiteName = "AnimeProgressStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "progress"
        let anime = makeAnime(id: 101, episodeCount: 12)
        let store = AnimeProgressStore(defaults: defaults, storageKey: key)

        store.setWatchedEpisodeCount(15, for: anime)

        XCTAssertEqual(store.watchedEpisodeCount(for: anime), 12)
        let restored = AnimeProgressStore(defaults: defaults, storageKey: key)
        XCTAssertEqual(restored.watchedEpisodeCount(for: anime), 12)
    }

    func testUnknownEpisodeCountAllowsProgressAndNegativeValuesResetIt() {
        let suiteName = "AnimeProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let anime = makeAnime(id: 202, episodeCount: nil)
        let store = AnimeProgressStore(defaults: defaults, storageKey: "progress")

        store.setWatchedEpisodeCount(4, for: anime)
        XCTAssertEqual(store.watchedEpisodeCount(for: anime), 4)

        store.setWatchedEpisodeCount(-2, for: anime)
        XCTAssertEqual(store.watchedEpisodeCount(for: anime), 0)
    }

    func testResetProgressIsIdempotent() {
        let suiteName = "AnimeProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let anime = makeAnime(id: 303, episodeCount: 24)
        let store = AnimeProgressStore(defaults: defaults, storageKey: "progress")

        store.setWatchedEpisodeCount(8, for: anime)
        store.resetProgress(for: anime.id)
        store.resetProgress(for: anime.id)

        XCTAssertEqual(store.watchedEpisodeCount(for: anime), 0)
    }

    private func makeAnime(id: Int, episodeCount: Int?) -> AnimeTitle {
        AnimeTitle(
            id: id,
            title: "Test Anime",
            nativeTitle: nil,
            synopsis: "",
            episodeCount: episodeCount,
            seasonYear: 2025,
            averageRating: 8.1,
            coverURL: nil,
            genres: [],
            format: "TV",
            status: "FINISHED"
        )
    }
}
