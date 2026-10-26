import XCTest
@testable import CineNex

final class ArtworkDiskCacheTests: XCTestCase {
    func testStoredArtworkSurvivesCacheObjectRecreationAndClears() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://example.test/poster.jpg?private=value")!
        let cache = ArtworkDiskCache(directory: directory)
        await cache.store(Data([1, 2, 3]), for: url)
        let recreated = ArtworkDiskCache(directory: directory)
        let data = await recreated.cachedData(for: url)
        XCTAssertEqual(data, Data([1, 2, 3]))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).joined().contains("private"))
        await recreated.clear()
        let missing = await cache.cachedData(for: url)
        XCTAssertNil(missing)
    }
    func testExpiredAndOversizeArtworkIsNotReused() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ArtworkDiskCache(directory: directory, maximumBytes: 2, lifetime: 1)
        let url = URL(string: "https://example.test/poster")!
        await cache.store(Data([1, 2, 3]), for: url)
        let oversize = await cache.cachedData(for: url)
        XCTAssertNil(oversize)
        await cache.store(Data([1]), for: url)
        let expired = await cache.cachedData(for: url, now: Date().addingTimeInterval(2))
        XCTAssertNil(expired)
    }
}
