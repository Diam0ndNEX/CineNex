import XCTest
@testable import CineNex

final class TorrentCacheMaintenanceTests: XCTestCase {
    func testClearingProtectsEveryActiveUserOfSameTorrent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(String(repeating: "a", count: 40))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("video"))
        let cache = TorrentCacheMaintenance(directory: directory, budget: 0)
        await cache.register(root)
        await cache.register(root)
        await cache.release(root, removeIfUnused: true)
        await cache.trim(clear: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        await cache.release(root, removeIfUnused: true)
        await cache.trim(clear: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
