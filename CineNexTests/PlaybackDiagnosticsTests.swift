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

    func testFrequentPieceTelemetryDoesNotEvictProviderOrAttemptEvents() {
        PlaybackDiagnostics.clear()
        PlaybackDiagnostics.record("discovery.provider.result", details: ["provider": "MediaFusion", "returned": "5"])
        PlaybackDiagnostics.beginAttempt(provider: "MediaFusion", fileIndex: 0)
        for index in 0..<1_000 {
            PlaybackDiagnostics.sample("torrent.pieces.wait", details: ["from": String(index)])
        }
        XCTAssertTrue(PlaybackDiagnostics.events.contains { $0.contains("discovery.provider.result") })
        XCTAssertTrue(PlaybackDiagnostics.events.contains { $0.contains("playback.attempt.begin") })
        XCTAssertEqual(PlaybackDiagnostics.events.filter { $0.contains("torrent.pieces.wait") }.count, 1)
        PlaybackDiagnostics.clear()
    }

    func testReportIdentifiesDiagnosticsSchemaAndNativeSection() {
        let report = PlaybackDiagnostics.report
        XCTAssertTrue(report.contains("playback report v3"))
        XCTAssertTrue(report.contains("NATIVE SESSION EVENTS"))
        XCTAssertTrue(report.contains("Physical memory"))
    }
}
