import XCTest
@testable import CineNex

@MainActor
final class PlaybackProgressStoreTests: XCTestCase {
    private func makeStore() -> (PlaybackProgressStore, UserDefaults, String) {
        let suite = "CineNexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PlaybackProgressStore(defaults: defaults, storageKey: "progress"), defaults, suite)
    }

    func testProgressPersistsAcrossStoreInstances() {
        let (store, defaults, suite) = makeStore()
        store.record(itemID: "sample", position: 42, duration: 100)
        let restored = PlaybackProgressStore(defaults: defaults, storageKey: "progress")
        XCTAssertEqual(restored.progress(for: "sample")?.position, 42)
        XCTAssertEqual(restored.progress(for: "sample")?.duration, 100)
        defaults.removePersistentDomain(forName: suite)
    }

    func testProgressRetainsItemSnapshotAcrossStoreRecreation() {
        let (store, defaults, suite) = makeStore()
        let item = MediaItem(
            id: "tmdb-movie-550",
            title: "Fight Club",
            kind: .movie,
            year: 1999,
            genre: "Drama",
            synopsis: "A saved title no longer present in trending results.",
            symbol: "film",
            runtime: "Movie",
            streamURL: URL(string: "https://example.com/fight-club.mp4"),
            posterURL: URL(string: "https://example.com/fight-club.jpg"),
            rating: 8.4,
            externalID: 550,
            metadataProvider: "tmdb"
        )

        store.record(itemID: item.id, position: 42, duration: 100, item: item)

        let restored = PlaybackProgressStore(defaults: defaults, storageKey: "progress")
        XCTAssertEqual(restored.progress(for: item.id)?.itemSnapshot, item)
        XCTAssertEqual(restored.progress(for: item.id)?.position, 42)
        defaults.removePersistentDomain(forName: suite)
    }

    func testTinyAndInvalidPositionsAreIgnored() {
        let (store, defaults, suite) = makeStore()
        store.record(itemID: "sample", position: 4.9, duration: 100)
        store.record(itemID: "invalid", position: .nan, duration: 100)
        store.record(itemID: "negative", position: -2, duration: 100)
        store.record(itemID: "   ", position: 20, duration: 100)
        XCTAssertTrue(store.entries.isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }

    func testNearCompletionRemovesProgress() {
        let (store, defaults, suite) = makeStore()
        store.record(itemID: "sample", position: 40, duration: 100)
        store.record(itemID: "sample", position: 75, duration: 100)
        XCTAssertNil(store.progress(for: "sample"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnknownDurationPreservesKnownDuration() {
        let (store, defaults, suite) = makeStore()
        store.record(itemID: "sample", position: 42, duration: 100)
        store.record(itemID: "sample", position: 50, duration: 0)
        XCTAssertEqual(store.progress(for: "sample")?.duration, 100)
        defaults.removePersistentDomain(forName: suite)
    }

    func testRemovingProgressPersists() {
        let (store, defaults, suite) = makeStore()
        store.record(itemID: "sample", position: 42, duration: 100)
        store.remove(itemID: "sample")
        let restored = PlaybackProgressStore(defaults: defaults, storageKey: "progress")
        XCTAssertNil(restored.progress(for: "sample"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testLoadingSanitizesInvalidAndCompletedStoredRecords() throws {
        let (store, defaults, suite) = makeStore()
        let storedRecords: [String: [String: Any]] = [
            "valid": [
                "itemID": "valid",
                "position": 42.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ],
            "empty-id": [
                "itemID": "",
                "position": 42.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ],
            "whitespace-id": [
                "itemID": "   ",
                "position": 42.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ],
            "negative-position": [
                "itemID": "negative-position",
                "position": -1.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ],
            "negative-duration": [
                "itemID": "negative-duration",
                "position": 42.0,
                "duration": -1.0,
                "updatedAt": 1_750_000_000.0
            ],
            "completed": [
                "itemID": "completed",
                "position": 75.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ],
            "beyond-duration": [
                "itemID": "beyond-duration",
                "position": 120.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ],
            "mismatched-key": [
                "itemID": "different-id",
                "position": 42.0,
                "duration": 100.0,
                "updatedAt": 1_750_000_000.0
            ]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: storedRecords), forKey: "progress")

        let restored = PlaybackProgressStore(defaults: defaults, storageKey: "progress")

        XCTAssertEqual(Set(restored.entries.keys), ["valid"])
        XCTAssertEqual(restored.progress(for: "valid")?.position, 42)
        XCTAssertNil(restored.progress(for: "completed"))
        XCTAssertNil(restored.progress(for: "beyond-duration"))
        defaults.removePersistentDomain(forName: suite)
        _ = store
    }

    func testProgressHistoryIsBoundedToTheMostRecentlyUpdatedHundredEntries() throws {
        let (store, defaults, suite) = makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var records: [String: PlaybackProgress] = [:]
        for index in 0..<120 {
            let itemID = "item-" + String(index)
            records[itemID] = PlaybackProgress(itemID: itemID, position: 20, duration: 100, updatedAt: start.addingTimeInterval(TimeInterval(index)))
        }
        defaults.set(try JSONEncoder().encode(records), forKey: "progress")
        let restored = PlaybackProgressStore(defaults: defaults, storageKey: "progress")
        XCTAssertEqual(restored.entries.count, 100)
        XCTAssertNotNil(restored.progress(for: "item-119"))
        XCTAssertNotNil(restored.progress(for: "item-20"))
        XCTAssertNil(restored.progress(for: "item-19"))
        restored.record(itemID: "new-item", position: 25, duration: 100)
        XCTAssertEqual(restored.entries.count, 100)
        XCTAssertNotNil(restored.progress(for: "new-item"))
        XCTAssertNil(restored.progress(for: "item-20"))
        let persisted = PlaybackProgressStore(defaults: defaults, storageKey: "progress")
        XCTAssertNotNil(persisted.progress(for: "new-item"))
        XCTAssertNil(persisted.progress(for: "item-20"))
        defaults.removePersistentDomain(forName: suite)
        _ = store
    }
    func testLoadingMalformedStoredDataProducesEmptyProgress() {
        let (store, defaults, suite) = makeStore()
        defaults.set(Data("{invalid-json".utf8), forKey: "progress")

        let restored = PlaybackProgressStore(defaults: defaults, storageKey: "progress")

        XCTAssertTrue(restored.entries.isEmpty)
        defaults.removePersistentDomain(forName: suite)
        _ = store
    }
}
