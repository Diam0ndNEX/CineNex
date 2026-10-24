import Foundation
import XCTest
@testable import CineNex

final class StremioTorrentDescriptorTests: XCTestCase {
    private let validHash = "0123456789abcdef0123456789abcdef01234567"

    func testNormalizesHashAndPreservesOptionalFileIndex() throws {
        let descriptor = try XCTUnwrap(
            StremioTorrentDescriptor(infoHash: "  \(validHash.uppercased())  ", fileIndex: 2)
        )

        XCTAssertEqual(descriptor.infoHash, validHash)
        XCTAssertEqual(descriptor.fileIndex, 2)
        XCTAssertEqual(descriptor.id, "\(validHash):2")
    }

    func testBuildsValidMagnetURLWithoutEmbeddingFileSelection() throws {
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(infoHash: validHash, fileIndex: 4))

        let components = try XCTUnwrap(URLComponents(url: descriptor.magnetURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "magnet")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "xt" })?.value, "urn:btih:\(validHash)")
        XCTAssertEqual(descriptor.fileIndex, 4)
    }

    func testAllowsTorrentWithoutFileIndex() throws {
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(infoHash: validHash, fileIndex: nil))

        XCTAssertNil(descriptor.fileIndex)
        XCTAssertEqual(descriptor.id, "\(validHash):all")
    }

    func testRejectsMissingMalformedAndWrongLengthHashes() {
        XCTAssertNil(StremioTorrentDescriptor(infoHash: nil, fileIndex: nil))
        XCTAssertNil(StremioTorrentDescriptor(infoHash: "", fileIndex: nil))
        XCTAssertNil(StremioTorrentDescriptor(infoHash: String(repeating: "a", count: 39), fileIndex: nil))
        XCTAssertNil(StremioTorrentDescriptor(infoHash: String(repeating: "a", count: 41), fileIndex: nil))
        XCTAssertNil(StremioTorrentDescriptor(infoHash: String(repeating: "g", count: 40), fileIndex: nil))
        XCTAssertNil(StremioTorrentDescriptor(infoHash: "0123456789abcdef0123456789abcdef0123456/", fileIndex: nil))
    }

    func testRejectsNegativeFileIndex() {
        XCTAssertNil(StremioTorrentDescriptor(infoHash: validHash, fileIndex: -1))
    }

    func testCreatesDescriptorDirectlyFromStremioStreamEntry() throws {
        let stream = try JSONDecoder().decode(
            StremioStreamEntry.self,
            from: Data(#"{"name":"Torrent","infoHash":"0123456789ABCDEF0123456789ABCDEF01234567","fileIdx":3}"#.utf8)
        )

        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream))
        XCTAssertEqual(descriptor.infoHash, validHash)
        XCTAssertEqual(descriptor.fileIndex, 3)
    }

    func testRejectsDirectStreamWithoutTorrentHash() throws {
        let stream = try JSONDecoder().decode(
            StremioStreamEntry.self,
            from: Data(#"{"name":"Direct","url":"https://media.example.test/movie.mp4"}"#.utf8)
        )

        XCTAssertNil(StremioTorrentDescriptor(stream: stream))
    }
}
