import XCTest
@testable import CineNex

final class OfflineDownloadTests: XCTestCase {
    func testOnlyHTTPSHLSPlaylistsAreEligible() {
        XCTAssertTrue(
            OfflineDownloadStore.supportsOfflineDownload(
                from: URL(string: "https://media.example.org/season-1/episode-1.m3u8")!
            )
        )
        XCTAssertFalse(
            OfflineDownloadStore.supportsOfflineDownload(
                from: URL(string: "http://media.example.org/episode.m3u8")!
            )
        )
        XCTAssertFalse(
            OfflineDownloadStore.supportsOfflineDownload(
                from: URL(string: "https://media.example.org/movie.mp4")!
            )
        )
        XCTAssertFalse(
            OfflineDownloadStore.supportsOfflineDownload(
                from: URL(string: "file:///tmp/episode.m3u8")!
            )
        )
    }

    func testOfflineDownloadRecordRoundTripsThroughCodable() throws {
        let createdAt = Date(timeIntervalSince1970: 1_760_000_000)
        let record = OfflineDownload(
            id: "download-1",
            title: "Example Episode",
            sourceURL: URL(string: "https://media.example.org/episode.m3u8")!,
            createdAt: createdAt,
            updatedAt: createdAt,
            status: .downloading,
            progress: 0.45,
            localDirectoryName: nil,
            errorMessage: nil
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(OfflineDownload.self, from: encoded)

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.status, .downloading)
        XCTAssertEqual(decoded.progress, 0.45)
    }

    func testPausedDownloadStatusRoundTripsThroughCodable() throws {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let record = OfflineDownload(
            id: "download-paused",
            title: "Paused Episode",
            sourceURL: URL(string: "https://media.example.org/paused.m3u8")!,
            createdAt: date,
            updatedAt: date,
            status: .paused,
            progress: 0.45,
            localDirectoryName: nil,
            errorMessage: nil
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(OfflineDownload.self, from: encoded)

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.status, .paused)
        XCTAssertEqual(decoded.progress, 0.45)
    }

    func testDirectorySizeCountsRegularFilesRecursively() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("segments", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 0x41, count: 1_024).write(to: root.appendingPathComponent("playlist.bin"))
        try Data(repeating: 0x42, count: 256).write(to: nested.appendingPathComponent("segment.bin"))

        XCTAssertEqual(OfflineDownloadStore.directorySize(at: root), 1_280)
    }

    func testDirectorySizeReturnsZeroForMissingPath() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertEqual(OfflineDownloadStore.directorySize(at: missing), 0)
    }

    func testCompletedDownloadOnlyExposesAnExistingLocalDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let record = OfflineDownload(
            id: "download-2",
            title: "Example Film",
            sourceURL: URL(string: "https://media.example.org/film.m3u8")!,
            createdAt: Date(),
            updatedAt: Date(),
            status: .completed,
            progress: 1,
            localDirectoryName: "download-2.movpkg",
            errorMessage: nil
        )

        XCTAssertNil(record.localAssetURL(in: root))
        let localDirectory = root.appendingPathComponent("download-2.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        XCTAssertEqual(record.localAssetURL(in: root), localDirectory)
    }

    @MainActor
    func testRemoveCompletedDownloadsDeletesMediaAndPreservesActiveRecords() throws {
        let suiteName = "OfflineDownloadTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let completedDirectory = root.appendingPathComponent("completed.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: completedDirectory, withIntermediateDirectories: true)
        try Data([0x01, 0x02, 0x03]).write(to: completedDirectory.appendingPathComponent("segment.bin"))

        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let completed = OfflineDownload(
            id: "completed",
            title: "Completed Film",
            sourceURL: URL(string: "https://media.example.org/completed.m3u8")!,
            createdAt: date,
            updatedAt: date,
            status: .completed,
            progress: 1,
            localDirectoryName: "completed.movpkg",
            errorMessage: nil
        )
        let failed = OfflineDownload(
            id: "failed",
            title: "Failed Film",
            sourceURL: URL(string: "https://media.example.org/failed.m3u8")!,
            createdAt: date.addingTimeInterval(1),
            updatedAt: date,
            status: .failed,
            progress: 0,
            localDirectoryName: nil,
            errorMessage: "Previous download failed"
        )
        let paused = OfflineDownload(
            id: "paused",
            title: "Paused Film",
            sourceURL: URL(string: "https://media.example.org/paused.m3u8")!,
            createdAt: date.addingTimeInterval(2),
            updatedAt: date,
            status: .paused,
            progress: 0.4,
            localDirectoryName: nil,
            errorMessage: nil
        )
        defaults.set(try JSONEncoder().encode([completed, failed, paused]), forKey: "offline.test.records")

        let store = OfflineDownloadStore(
            defaults: defaults,
            storageKey: "offline.test.records",
            downloadsDirectory: root
        )

        XCTAssertEqual(store.removeCompletedDownloads(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedDirectory.path))
        XCTAssertEqual(Set(store.downloads.map(\.id)), Set(["failed", "paused"]))
        XCTAssertEqual(store.downloads.first(where: { $0.id == "failed" })?.status, .failed)
        XCTAssertEqual(store.downloads.first(where: { $0.id == "paused" })?.status, .paused)

        let persistedData = try XCTUnwrap(defaults.data(forKey: "offline.test.records"))
        let persistedRecords = try JSONDecoder().decode([OfflineDownload].self, from: persistedData)
        XCTAssertEqual(Set(persistedRecords.map(\.id)), Set(["failed", "paused"]))
    }

    @MainActor
    func testRemoveCompletedDownloadsReturnsZeroWhenNoneAreCompleted() throws {
        let suiteName = "OfflineDownloadTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let queued = OfflineDownload(
            id: "queued",
            title: "Queued Film",
            sourceURL: URL(string: "https://media.example.org/queued.m3u8")!,
            createdAt: date,
            updatedAt: date,
            status: .queued,
            progress: 0,
            localDirectoryName: nil,
            errorMessage: nil
        )
        defaults.set(try JSONEncoder().encode([queued]), forKey: "offline.test.records")

        let store = OfflineDownloadStore(
            defaults: defaults,
            storageKey: "offline.test.records",
            downloadsDirectory: root
        )

        XCTAssertEqual(store.removeCompletedDownloads(), 0)
        XCTAssertEqual(store.downloads, [queued])
    }

}
