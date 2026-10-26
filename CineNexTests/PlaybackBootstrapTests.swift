import XCTest
@testable import CineNex

final class PlaybackBootstrapTests: XCTestCase {
    @MainActor
    func testVLCPlayerCanInitializeAndFinishTeardown() async throws {
        let player = try await VLCPlaybackRuntime.makePlayer()
        await player.stopAndWait()
    }
}
