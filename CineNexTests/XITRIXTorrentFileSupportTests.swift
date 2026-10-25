import Foundation
import XCTest
@testable import CineNex

final class XITRIXTorrentFileSupportTests: XCTestCase {
    func testAcceptsNativeAVPlayerFileTypes() {
        for path in ["movie.mp4", "movie.m4v", "movie.mov", "track.mp3", "track.m4a", "track.aac", "track.wav"] {
            XCTAssertTrue(XITRIXTorrentFileSupport.isPlayableFile(path), path)
            XCTAssertNotNil(XITRIXTorrentFileSupport.contentType(for: path), path)
        }
    }

    func testRejectsContainersNotSupportedByNativeAVPlayer() {
        for path in ["movie.mkv", "movie.avi", "movie.webm", "notes.txt", "folder/movie"] {
            XCTAssertFalse(XITRIXTorrentFileSupport.isPlayableFile(path), path)
            XCTAssertNil(XITRIXTorrentFileSupport.contentType(for: path), path)
        }
    }

    func testResolvesSafeRelativePathInsideDownloadRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/CineNex/Torrents/abc", isDirectory: true)
        let file = try XCTUnwrap(XITRIXTorrentFileSupport.safeFileURL(root: root, relativePath: "Folder/movie.mp4"))

        XCTAssertEqual(file.path, "/tmp/CineNex/Torrents/abc/Folder/movie.mp4")
    }

    func testRejectsSymlinkThatEscapesDownloadRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinenex-torrent-path-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let outside = base.appendingPathComponent("outside.mp4")
        let link = root.appendingPathComponent("escape.mp4")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertNil(XITRIXTorrentFileSupport.safeFileURL(root: root, relativePath: "escape.mp4"))
    }

    func testRejectsPathTraversalAndAbsolutePaths() {
        let root = URL(fileURLWithPath: "/tmp/CineNex/Torrents/abc", isDirectory: true)
        let unsafePaths = ["../outside.mp4", "Folder/../../outside.mp4", "/tmp/outside.mp4", "Folder\\outside.mp4", ""]

        for path in unsafePaths {
            XCTAssertNil(XITRIXTorrentFileSupport.safeFileURL(root: root, relativePath: path), path)
        }
    }
}
