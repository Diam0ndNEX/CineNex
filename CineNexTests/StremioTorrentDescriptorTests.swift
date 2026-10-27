import Foundation
import XCTest
@testable import CineNex

final class StremioTorrentDescriptorTests: XCTestCase {
    func testMediaFusionMetadataSurvivesSeparateDescriptionAndName() throws {
        let json = #"{"title":"Example release","description":"👤 1,234 💾 1.4 GB","name":"MediaFusion 1080p","infoHash":"0123456789abcdef0123456789abcdef01234567"}"#
        let stream = try JSONDecoder().decode(StremioStreamEntry.self, from: Data(json.utf8))
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream, providerName: "MediaFusion"))
        XCTAssertEqual(descriptor.title, "Example release")
        XCTAssertEqual(SceneBoxStreamPicker.resolution(for: descriptor), "1080p")
        XCTAssertEqual(SceneBoxStreamPicker.seeders(for: descriptor), 1234)
        XCTAssertEqual(SceneBoxStreamPicker.size(for: descriptor), "1.4 GB")
        XCTAssertEqual(SceneBoxStreamPicker.sizeBytes(for: descriptor), 1_400_000_000)
    }

    func testStructuredSizeAndSeederMetadataArePreserved() throws {
        let json = #"{"title":"Example release","seeders":0,"infoHash":"0123456789abcdef0123456789abcdef01234567","behaviorHints":{"videoSize":2300000000}}"#
        let stream = try JSONDecoder().decode(StremioStreamEntry.self, from: Data(json.utf8))
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream))
        XCTAssertEqual(descriptor.reportedSeeders, 0)
        XCTAssertEqual(descriptor.reportedSizeBytes, 2_300_000_000)
        XCTAssertEqual(descriptor.sizeLabel, "2.30 GB")
        XCTAssertNil(descriptor.resolutionLabel)
    }

    func testInvalidStructuredMetadataDoesNotInventValues() throws {
        let json = #"{"title":"Example release","seeders":-2,"infoHash":"0123456789abcdef0123456789abcdef01234567","behaviorHints":{"videoSize":-1}}"#
        let stream = try JSONDecoder().decode(StremioStreamEntry.self, from: Data(json.utf8))
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream))
        XCTAssertNil(descriptor.reportedSeeders)
        XCTAssertNil(descriptor.reportedSizeBytes)
        XCTAssertNil(descriptor.sizeLabel)
    }

    private let validHash = "0123456789abcdef0123456789abcdef01234567"

    func testNormalizesHashAndPreservesOptionalFileIndex() throws {
        let descriptor = try XCTUnwrap(
            StremioTorrentDescriptor(infoHash: "  \(validHash.uppercased())  ", fileIndex: 2)
        )

        XCTAssertEqual(descriptor.infoHash, validHash)
        XCTAssertEqual(descriptor.fileIndex, 2)
        XCTAssertEqual(descriptor.id, "stremio-add-on:\(validHash):2")
    }

    func testSameTorrentFromDifferentProvidersHasDifferentIdentity() throws {
        let torrentio = try XCTUnwrap(
            StremioTorrentDescriptor(infoHash: validHash, fileIndex: 0, providerName: "Torrentio")
        )
        let mediaFusion = try XCTUnwrap(
            StremioTorrentDescriptor(infoHash: validHash, fileIndex: 0, providerName: "MediaFusion")
        )

        XCTAssertEqual(torrentio.infoHash, mediaFusion.infoHash)
        XCTAssertEqual(torrentio.fileIndex, mediaFusion.fileIndex)
        XCTAssertNotEqual(torrentio.id, mediaFusion.id)
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
        XCTAssertEqual(descriptor.id, "stremio-add-on:\(validHash):all")
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
            from: Data(#"{"name":"Ghost Torrents · 1080p","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":3,"sources":["tracker:udp://tracker.example.test:80/announce"],"behaviorHints":{"filename":"0123456789abcdef0123456789abcdef01234567.mp4"}}"#.utf8)
        )
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream))
        XCTAssertEqual(descriptor.infoHash, validHash)
        XCTAssertEqual(descriptor.fileIndex, 3)
        XCTAssertEqual(descriptor.title, "Ghost Torrents · 1080p")
        XCTAssertEqual(descriptor.trackers.map(\.absoluteString), ["udp://tracker.example.test:80/announce"])
        let magnet = try XCTUnwrap(URLComponents(url: descriptor.magnetURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(magnet.queryItems?.filter { $0.name == "tr" }.compactMap(\.value), ["udp://tracker.example.test:80/announce"])
    }

    func testRejectsUnsafeTrackersAndCapsDuplicateTrackers() throws {
        let safe = try XCTUnwrap(URL(string: "https://tracker.example.test/announce"))
        let unsafe = try XCTUnwrap(URL(string: "https://user:pass@tracker.example.test/announce"))
        let many = Array(repeating: safe, count: 25) + [unsafe]
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(infoHash: validHash, fileIndex: nil, trackers: many))

        XCTAssertEqual(descriptor.trackers, [safe])
        let components = try XCTUnwrap(URLComponents(url: descriptor.magnetURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.filter { $0.name == "tr" }.count, 1)
    }

    func testPrefersReleaseTitleOverAddonNameAndOpaqueFilename() throws {
        let stream = try JSONDecoder().decode(
            StremioStreamEntry.self,
            from: Data(#"{"name":"Torrentio · 1080p · 1234567890abcdef1234567890abcdef12345678","title":"Ghost Torrents S01E02 1080p","infoHash":"0123456789abcdef0123456789abcdef01234567","behaviorHints":{"filename":"0123456789abcdef0123456789abcdef01234567.mp4"}}"#.utf8)
        )
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream, providerName: "Torrentio"))
        XCTAssertEqual(descriptor.title, "Ghost Torrents S01E02 1080p")
        XCTAssertEqual(descriptor.providerName, "Torrentio")
    }

    func testPreservesReadableTorrentTitleAndProviderName() throws {
        let stream = try JSONDecoder().decode(
            StremioStreamEntry.self,
            from: Data(#"{"name":"Ghost Torrents · 1080p","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":3}"#.utf8)
        )
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(stream: stream, providerName: "Torrentio"))
        XCTAssertEqual(descriptor.title, "Ghost Torrents · 1080p")
        XCTAssertEqual(descriptor.providerName, "Torrentio")
        XCTAssertFalse(descriptor.title.contains(descriptor.infoHash))
    }

    func testRejectsDirectStreamWithoutTorrentHash() throws {
        let stream = try JSONDecoder().decode(
            StremioStreamEntry.self,
            from: Data(#"{"name":"Direct","url":"https://media.example.test/movie.mp4"}"#.utf8)
        )

        XCTAssertNil(StremioTorrentDescriptor(stream: stream))
    }
}
