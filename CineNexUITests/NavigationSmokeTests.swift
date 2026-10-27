import XCTest

/// Deterministic navigation evidence: the app's DEBUG fixture mode avoids provider/network waits.
final class NavigationSmokeTests: XCTestCase {
    @MainActor
    func testSingleDockSettingsLibraryDetailAndGenreRoutes() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke"]
        app.launch()

        let home = app.buttons["navigation.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        assertSingleDock(app)
        capture(app, name: "01-Home")

        app.buttons["navigation.profile"].tap()
        let search = app.textFields["settings.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        assertSingleDock(app)
        capture(app, name: "02-Settings")
        search.tap()
        search.typeText("subtitles")
        let playback = app.buttons["settings.category.playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings.category.appearance"].exists)
        playback.tap()
        XCTAssertTrue(app.navigationBars["Playback"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if let value = search.value as? String, value == "subtitles" {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        let appearance = app.buttons["settings.category.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        for _ in 0..<3 where !appearance.isHittable { app.swipeUp() }
        appearance.tap()
        XCTAssertTrue(app.navigationBars["Appearance & layout"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["navigation.library"].tap()
        assertSingleDock(app)
        capture(app, name: "03-Library")

        home.tap()
        let fixture = app.buttons["title.big-buck-bunny"].firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        // The fixture can be in a shelf below the spotlight, depending on display size.
        for _ in 0..<3 where !fixture.isHittable { app.swipeUp() }
        XCTAssertTrue(fixture.isHittable)
        fixture.tap()
        let genre = app.buttons["detail.genre.Animation"]
        XCTAssertTrue(genre.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0, "Details must not reveal a second native tab bar")
        capture(app, name: "04-Detail")
        genre.tap()
        XCTAssertTrue(app.navigationBars["Animation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["title.big-buck-bunny"].firstMatch.waitForExistence(timeout: 5),
                      "The genre route must immediately expose matching fixture titles")
        capture(app, name: "05-Genre")
        app.terminate()
    }

    @MainActor
    private func assertSingleDock(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.otherElements.matching(identifier: "root.navigation").count, 1,
                       "Each root screen must contain exactly one custom navigation dock", file: file, line: line)
        XCTAssertEqual(app.tabBars.count, 0, "A native tab bar would duplicate the custom dock", file: file, line: line)
        for identifier in ["navigation.home", "navigation.search", "navigation.library", "navigation.profile"] {
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1, file: file, line: line)
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
