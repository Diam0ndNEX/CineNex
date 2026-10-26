import XCTest
@testable import CineNex

final class PlaybackPreferencesTests: XCTestCase {
    func testInvalidSavedPlaybackValuesFallBackSafely() {
        XCTAssertEqual(PlaybackPreferences.skipSeconds(-30), 10)
        XCTAssertEqual(PlaybackPreferences.skipSeconds(15), 15)
        XCTAssertEqual(PlaybackPreferences.speed(.nan), 1)
        XCTAssertEqual(PlaybackPreferences.speed(100), 1)
        XCTAssertEqual(PlaybackPreferences.speed(1.25), 1.25)
    }
    func testTransferCeilingsUseBytesAndUnlimitedIsExplicit() {
        XCTAssertEqual(TorrentTransferProfile.economy.downloadBytesPerSecond, 4_194_304)
        XCTAssertGreaterThan(TorrentTransferProfile.balanced.downloadBytesPerSecond, TorrentTransferProfile.economy.downloadBytesPerSecond)
        XCTAssertEqual(TorrentTransferProfile.unlimited.downloadBytesPerSecond, 0)
        XCTAssertGreaterThan(TorrentTransferProfile.balanced.uploadBytesPerSecond, 0)
    }
}
