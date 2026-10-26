import XCTest
@testable import CineNex

final class SceneBoxStreamPickerTests: XCTestCase {
    func testPrefersRequestedResolutionWhenSeedersMeetSceneBoxThreshold() throws {
        let lowSeedHighResolution = try XCTUnwrap(
            StremioTorrentDescriptor(
                infoHash: "1111111111111111111111111111111111111111",
                fileIndex: 0,
                title: "2160p WEB-DL 👤 2 💾 8 GB",
                providerName: "Torrentio"
            )
        )
        let matchingResolution = try XCTUnwrap(
            StremioTorrentDescriptor(
                infoHash: "2222222222222222222222222222222222222222",
                fileIndex: 0,
                title: "1080p WEB-DL 👤 12 💾 3 GB",
                providerName: "Torrentio"
            )
        )

        let ordered = SceneBoxStreamPicker.ordered(
            [lowSeedHighResolution, matchingResolution],
            preferredResolution: "1080p"
        )

        XCTAssertEqual(ordered.first?.id, matchingResolution.id)
    }

    func testExtractsResolutionSeedersAndSizeFromTorrentioTitle() throws {
        let descriptor = try XCTUnwrap(
            StremioTorrentDescriptor(
                infoHash: "3333333333333333333333333333333333333333",
                fileIndex: 1,
                title: "Anime 1080p HEVC 👤 42 💾 1.4 GB",
                providerName: "Torrentio"
            )
        )

        XCTAssertEqual(SceneBoxStreamPicker.resolution(for: descriptor), "1080p")
        XCTAssertEqual(SceneBoxStreamPicker.seeders(for: descriptor), 42)
        XCTAssertEqual(SceneBoxStreamPicker.size(for: descriptor), "1.4 GB")
    }

    func testUnknownMetadataDoesNotCrashOrInventValues() throws {
        let descriptor = try XCTUnwrap(
            StremioTorrentDescriptor(
                infoHash: "4444444444444444444444444444444444444444",
                fileIndex: nil,
                title: "Torrent stream",
                providerName: "MediaFusion"
            )
        )

        XCTAssertNil(SceneBoxStreamPicker.resolution(for: descriptor))
        XCTAssertNil(SceneBoxStreamPicker.seeders(for: descriptor))
        XCTAssertNil(SceneBoxStreamPicker.size(for: descriptor))
        XCTAssertEqual(SceneBoxStreamPicker.ordered([descriptor]).map(\.id), [descriptor.id])
    }
}
