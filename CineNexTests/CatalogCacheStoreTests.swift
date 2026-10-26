import XCTest
@testable import CineNex

@MainActor
final class CatalogCacheStoreTests: XCTestCase {
    private func makeStore() -> (CatalogCacheStore, UserDefaults, String) {
        let suite = "CineNexCatalogCacheTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CatalogCacheStore(defaults: defaults, storageKey: "catalogCache"), defaults, suite)
    }

    func testCatalogCacheSurvivesStoreRecreation() {
        let (store, defaults, suite) = makeStore()
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let items = MediaItem.demoCatalog
        store.save(items, savedAt: savedAt)
        let restored = CatalogCacheStore(defaults: defaults, storageKey: "catalogCache").load()
        XCTAssertEqual(restored?.items, items)
        XCTAssertEqual(restored?.savedAt, savedAt)
        defaults.removePersistentDomain(forName: suite)
    }

    func testEmptyOrDuplicateCatalogDoesNotReplaceExistingCache() {
        let (store, defaults, suite) = makeStore()
        let existing = MediaItem.demoCatalog
        store.save(existing)
        store.save([])
        let duplicate = existing[0]
        store.save([duplicate, duplicate])
        XCTAssertEqual(store.load()?.items, existing)
        defaults.removePersistentDomain(forName: suite)
    }

    func testSnapshotFreshnessRejectsExpiredFutureAndInvalidAges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = CachedCatalogSnapshot(items: MediaItem.demoCatalog, savedAt: now.addingTimeInterval(-60))
        let expired = CachedCatalogSnapshot(items: MediaItem.demoCatalog, savedAt: now.addingTimeInterval(-121))
        let future = CachedCatalogSnapshot(items: MediaItem.demoCatalog, savedAt: now.addingTimeInterval(1))
        XCTAssertTrue(fresh.isFresh(maxAge: 60, now: now))
        XCTAssertFalse(expired.isFresh(maxAge: 120, now: now))
        XCTAssertFalse(future.isFresh(maxAge: 300, now: now))
        XCTAssertFalse(fresh.isFresh(maxAge: -1, now: now))
        XCTAssertFalse(fresh.isFresh(maxAge: .infinity, now: now))
    }

    func testInvalidCacheDataReturnsNoSnapshot() {
        let (store, defaults, suite) = makeStore()
        defaults.set(Data("not-json".utf8), forKey: "catalogCache")
        XCTAssertNil(store.load())
        defaults.removePersistentDomain(forName: suite)
    }

    func testCacheRejectsItemsWithBlankIdentifiersOrTitles() {
        let (store, defaults, suite) = makeStore()
        let invalidItem = MediaItem(
            id: "invalid-id",
            title: "  ",
            kind: .movie,
            year: 2024,
            genre: "Drama",
            synopsis: "Invalid cache item.",
            symbol: "film",
            runtime: "Movie",
            streamURL: nil
        )
        store.save([invalidItem])
        XCTAssertNil(store.load())
        defaults.removePersistentDomain(forName: suite)
    }
}