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

    func testTinyAndInvalidPositionsAreIgnored() {
        let (store, defaults, suite) = makeStore()
        store.record(itemID: "sample", position: 4.9, duration: 100)
        store.record(itemID: "invalid", position: .nan, duration: 100)
        store.record(itemID: "negative", position: -2, duration: 100)
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
}
