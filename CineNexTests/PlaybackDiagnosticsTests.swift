import XCTest
@testable import CineNex

final class PlaybackDiagnosticsTests: XCTestCase {
    func testStartupDetailsRedactSourceAndConfigurationURLs() {
        PlaybackDiagnostics.beginAttempt(provider: "MediaFusion Midnight", fileIndex: 2)
        PlaybackDiagnostics.record("fixture", details: ["request": "https://example.test/private-token/manifest.json"])
        let event = PlaybackDiagnostics.events.last ?? ""
        XCTAssertTrue(event.contains("[redacted-url]"))
        XCTAssertFalse(event.contains("private-token"))
        XCTAssertTrue(event.contains("attempt="))
        XCTAssertTrue(event.contains("elapsed="))
    }

    func testReportIdentifiesDiagnosticsSchemaAndNativeSection() {
        let report = PlaybackDiagnostics.report
        XCTAssertTrue(report.contains("playback report v2"))
        XCTAssertTrue(report.contains("NATIVE SESSION EVENTS"))
        XCTAssertTrue(report.contains("Physical memory"))
    }
}
