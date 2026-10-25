import XCTest
@testable import CineNex

final class TorrentStreamTelemetryTests: XCTestCase {
    func testSnapshotTracksRequestsBytesFailuresAndReadLatency() {
        let telemetry = TorrentStreamTelemetry()
        telemetry.recordRequest(isRange: false)
        telemetry.recordRequest(isRange: true)
        telemetry.recordRequest(isRange: true)
        telemetry.recordBytesServed(128 * 1024)
        telemetry.recordBytesServed(12)
        telemetry.recordBytesServed(0)
        telemetry.recordFailure()
        telemetry.recordReadDuration(milliseconds: 35)
        telemetry.recordReadDuration(milliseconds: 120)
        telemetry.recordReadDuration(milliseconds: -1)
        telemetry.setActiveConnectionCount(3)

        XCTAssertEqual(
            telemetry.snapshot(),
            TorrentStreamTelemetrySnapshot(
                requestCount: 3,
                rangeRequestCount: 2,
                bytesServed: 128 * 1024 + 12,
                failedRequestCount: 1,
                activeConnectionCount: 3,
                totalReadMilliseconds: 155,
                maximumReadMilliseconds: 120
            )
        )
    }

    func testConnectionCountNeverBecomesNegative() {
        let telemetry = TorrentStreamTelemetry()
        telemetry.setActiveConnectionCount(-4)

        XCTAssertEqual(telemetry.snapshot().activeConnectionCount, 0)
    }

    func testConcurrentUpdatesRemainConsistent() {
        let telemetry = TorrentStreamTelemetry()
        DispatchQueue.concurrentPerform(iterations: 500) { index in
            telemetry.recordRequest(isRange: index.isMultiple(of: 2))
            telemetry.recordBytesServed(1)
            telemetry.recordReadDuration(milliseconds: 1)
            if index.isMultiple(of: 5) {
                telemetry.recordFailure()
            }
        }

        let snapshot = telemetry.snapshot()
        XCTAssertEqual(snapshot.requestCount, 500)
        XCTAssertEqual(snapshot.rangeRequestCount, 250)
        XCTAssertEqual(snapshot.bytesServed, 500)
        XCTAssertEqual(snapshot.failedRequestCount, 100)
        XCTAssertEqual(snapshot.totalReadMilliseconds, 500)
        XCTAssertEqual(snapshot.maximumReadMilliseconds, 1)
    }
}
