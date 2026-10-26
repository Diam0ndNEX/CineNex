import XCTest
@testable import CineNex

final class SceneBoxChromeVisibilityTests: XCTestCase {
    @MainActor
    func testPausedPlaybackKeepsControlsVisible() {
        let chrome = SceneBoxChromeVisibility()
        chrome.reveal(autoHide: false)
        XCTAssertTrue(chrome.isVisible)
        XCTAssertNil(chrome.autoHideID)
    }

    @MainActor
    func testSettingsHoldPreventsAutoHideUntilReleased() {
        let chrome = SceneBoxChromeVisibility()
        chrome.reveal(autoHide: true)
        XCTAssertNotNil(chrome.autoHideID)
        chrome.holdVisible()
        chrome.playbackStarted()
        chrome.interacted(autoHide: true)
        XCTAssertTrue(chrome.isVisible)
        XCTAssertNil(chrome.autoHideID)
        chrome.releaseHold(autoHide: true)
        XCTAssertNotNil(chrome.autoHideID)
    }

    @MainActor
    func testTapHidesThenRevealsControlsDuringPlayback() {
        let chrome = SceneBoxChromeVisibility()
        chrome.screenTapped(shouldAutoHide: true)
        XCTAssertFalse(chrome.isVisible)
        XCTAssertNil(chrome.autoHideID)
        chrome.screenTapped(shouldAutoHide: true)
        XCTAssertTrue(chrome.isVisible)
        XCTAssertNotNil(chrome.autoHideID)
    }

    @MainActor
    func testCancelledAutoHideDoesNotHideControls() async {
        let chrome = SceneBoxChromeVisibility()
        chrome.reveal(autoHide: true)
        let task = Task { await chrome.autoHide() }
        task.cancel()
        await task.value
        XCTAssertTrue(chrome.isVisible)
        chrome.viewDisappeared()
        XCTAssertNil(chrome.autoHideID)
    }
}
