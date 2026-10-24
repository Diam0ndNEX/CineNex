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
}
