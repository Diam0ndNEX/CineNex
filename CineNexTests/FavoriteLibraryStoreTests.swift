import XCTest
@testable import CineNex

final class FavoriteLibraryStoreTests: XCTestCase {
    private func makeStore() -> (FavoriteLibraryStore, UserDefaults, String) {
        let suite = "CineNexFavoriteTests.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (FavoriteLibraryStore(defaults: defaults, storageKey: "favoriteSnapshots"), defaults, suite)
    }

    func testFavoriteSnapshotSurvivesCatalogChangesAndStoreRecreation() {
        let (store, defaults, suite) = makeStore()
        let item = MediaItem(
            id: "tmdb-movie-550",
            title: "Fight Club",
            kind: .movie,
            year: 1999,
            genre: "Drama",
            synopsis: "A saved title that is no longer trending.",
            symbol: "film",
            runtime: "Movie",
            streamURL: nil,
            posterURL: URL(string: "https://image.tmdb.org/t/p/w500/fight-club.jpg"),
            rating: 8.4,
            externalID: 550,
            metadataProvider: "tmdb"
        )

        store.save(item)

        let restoredStore = FavoriteLibraryStore(defaults: defaults, storageKey: "favoriteSnapshots")
        let restored = restoredStore.load()["tmdb-movie-550"]
        XCTAssertEqual(restored, item)
        XCTAssertEqual(restored?.posterURL, item.posterURL)
        XCTAssertEqual(restored?.externalID, 550)
        XCTAssertNil(restored?.streamURL)

        defaults.removePersistentDomain(forName: suite)
    }

    func testRemovingFavoriteSnapshotPersists() {
        let (store, defaults, suite) = makeStore()
        let item = MediaItem.demoCatalog[0]
        store.save(item)
        store.remove(itemID: item.id)

        XCTAssertNil(FavoriteLibraryStore(defaults: defaults, storageKey: "favoriteSnapshots").load()[item.id])

        defaults.removePersistentDomain(forName: suite)
    }

    func testInvalidFavoriteSnapshotIsNotSaved() {
        let (store, defaults, suite) = makeStore()
        let item = MediaItem(
            id: "  ",
            title: "Invalid",
            kind: .movie,
            year: 2024,
            genre: "Drama",
            synopsis: "Invalid identifier.",
            symbol: "film",
            runtime: "Movie",
            streamURL: nil
        )

        store.save(item)

        XCTAssertTrue(store.load().isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }
}
