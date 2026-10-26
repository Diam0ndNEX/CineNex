import XCTest
@testable import CineNex

final class SceneBoxStreamPickerTests: XCTestCase {
    func testProviderAndQualityFiltersKeepOnlyExactMatches() throws {
        let wanted = try descriptor(1, provider: "MediaFusion Midnight", title: "1080p 👤 8 💾 2 GB")
        let otherProvider = try descriptor(2, provider: "Torrentio", title: "1080p 👤 40 💾 3 GB")
        let otherQuality = try descriptor(3, provider: "MediaFusion Midnight", title: "2160p 👤 5 💾 8 GB")
        let results = SceneBoxStreamPicker.filtered([wanted, otherProvider, otherQuality], provider: "MediaFusion Midnight", quality: "1080p")
        XCTAssertEqual(results.map(\.id), [wanted.id])
    }

    func testSeederSortPutsUnknownMetadataLast() throws {
        let unknown = try descriptor(1, title: "1080p")
        let zero = try descriptor(2, title: "1080p 👤 0")
        let active = try descriptor(3, title: "1080p 👤 12")
        let results = SceneBoxStreamPicker.filtered([unknown, zero, active], sort: .seeders)
        XCTAssertEqual(results.map(\.id), [active.id, zero.id, unknown.id])
    }

    func testSizeSortComparesUnitsAndPlacesUnknownLast() throws {
        let unknown = try descriptor(1, title: "1080p")
        let smaller = try descriptor(2, title: "720p 💾 800 MB")
        let larger = try descriptor(3, title: "1080p 💾 1.2 GB")
        let results = SceneBoxStreamPicker.filtered([unknown, larger, smaller], sort: .size)
        XCTAssertEqual(results.map(\.id), [smaller.id, larger.id, unknown.id])
        XCTAssertEqual(SceneBoxStreamPicker.sizeBytes(for: smaller), 800_000_000)
    }

    func testResolutionSortAndUnknownFilterDoNotInventQuality() throws {
        let unknown = try descriptor(1, title: "Unlabeled release")
        let fullHD = try descriptor(2, title: "1080p")
        let ultraHD = try descriptor(3, title: "4K")
        let streams = [unknown, fullHD, ultraHD]
        XCTAssertEqual(SceneBoxStreamPicker.filtered(streams, sort: .resolution).map(\.id), [ultraHD.id, fullHD.id, unknown.id])
        XCTAssertEqual(SceneBoxStreamPicker.filtered(streams, quality: "Unknown").map(\.id), [unknown.id])
    }

    func testSizeSortUsesMetadataFromDescriptionAndStructuredBytes() throws {
        let json = #"{"title":"Readable title","description":"Seeders: 24 · 800 MiB","name":"Add-on 720p","infoHash":"0123456789abcdef0123456789abcdef01234567"}"#
        let entry = try JSONDecoder().decode(StremioStreamEntry.self, from: Data(json.utf8))
        let smaller = try XCTUnwrap(StremioTorrentDescriptor(stream: entry))
        let larger = try XCTUnwrap(StremioTorrentDescriptor(infoHash: String(repeating: "a", count: 40), fileIndex: nil, videoSize: 1_000_000_000))
        XCTAssertEqual(SceneBoxStreamPicker.filtered([larger, smaller], sort: .size).map(\.id), [smaller.id, larger.id])
        XCTAssertEqual(SceneBoxStreamPicker.seeders(for: smaller), 24)
        XCTAssertEqual(SceneBoxStreamPicker.sizeBytes(for: smaller), 838_860_800)
    }

    private func descriptor(_ number: Int, provider: String = "Torrentio", title: String) throws -> StremioTorrentDescriptor {
        try XCTUnwrap(StremioTorrentDescriptor(infoHash: String(format: "%040x", number), fileIndex: 0, title: title, providerName: provider))
    }

    func testMediaFusionIsNotHiddenByTorrentioLimit() throws {
        let streams = try (0..<30).map { index in
            try XCTUnwrap(StremioTorrentDescriptor(
                infoHash: String(format: "%040x", index + 1), fileIndex: 0,
                title: "1080p 👤 20", providerName: "Torrentio"
            ))
        }
        let mediaFusion = try XCTUnwrap(StremioTorrentDescriptor(
            infoHash: String(repeating: "f", count: 40), fileIndex: 0,
            title: "1080p", providerName: "MediaFusion Midnight"
        ))
        let limited = SceneBoxStreamPicker.balanced(streams + [mediaFusion], limit: 12)
        XCTAssertEqual(limited.count, 12)
        XCTAssertTrue(limited.contains { $0.id == mediaFusion.id })
        XCTAssertEqual(limited[1].providerName, "MediaFusion Midnight")
        XCTAssertTrue(SceneBoxStreamPicker.balanced(streams, limit: 0).isEmpty)
    }

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
