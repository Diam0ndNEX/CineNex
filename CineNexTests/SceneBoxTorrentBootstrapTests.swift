import XCTest
@testable import CineNex

final class SceneBoxTorrentBootstrapTests: XCTestCase {
    func testUsesSceneBoxDiscoveryTrackersWithoutChangingStreamIdentity() throws {
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(
            infoHash: String(repeating: "a", count: 40), fileIndex: 3,
            title: "Example release", providerName: "MediaFusion Midnight"
        ))
        let result = try XCTUnwrap(SceneBoxTorrentBootstrap.withDefaultTrackers(descriptor))
        XCTAssertEqual(result.id, descriptor.id)
        XCTAssertEqual(result.fileIndex, 3)
        XCTAssertEqual(result.providerName, descriptor.providerName)
        XCTAssertFalse(result.trackers.isEmpty)
        XCTAssertTrue(result.magnetURL.absoluteString.contains("tr="))
    }

    func testPreservesProviderTrackerAndDeduplicatesDefaults() throws {
        let tracker = try XCTUnwrap(URL(string: "udp://tracker.opentrackr.org:1337/announce"))
        let descriptor = try XCTUnwrap(StremioTorrentDescriptor(
            infoHash: String(repeating: "b", count: 40), fileIndex: nil, trackers: [tracker]
        ))
        let result = try XCTUnwrap(SceneBoxTorrentBootstrap.withDefaultTrackers(descriptor))
        XCTAssertEqual(result.trackers.first, tracker)
        XCTAssertEqual(result.trackers.filter { $0 == tracker }.count, 1)
        XCTAssertLessThanOrEqual(result.trackers.count, 20)
    }
}
