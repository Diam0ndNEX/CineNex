import XCTest
@testable import CineNex

final class TorrentPlaybackMonitorTests: XCTestCase {
    func testStartupReadinessRequiresEveryHeadAndTailPieceRatherThanSparseFileExistence() {
        let required: Set<Int64> = [0, 1, 9]
        var pieces = Array(repeating: false, count: 10)
        pieces[0] = true
        pieces[1] = true
        let incomplete = TorrentStartupReadiness.counts(required: required, available: pieces)
        XCTAssertEqual(incomplete.ready, 2)
        XCTAssertEqual(incomplete.total, 3)
        pieces[9] = true
        let ready = TorrentStartupReadiness.counts(required: required, available: pieces)
        XCTAssertEqual(ready.ready, ready.total)
    }

    func testOutOfBoundsPiecesCannotBeDeclaredReady() {
        let counts = TorrentStartupReadiness.counts(required: [-1, 0, 7], available: [true])
        XCTAssertEqual(counts.ready, 1)
        XCTAssertEqual(counts.total, 3)
    }

    func testProgressIsUnknownUntilThereIsAnActualRequiredBuffer() {
        XCTAssertNil(TorrentPlaybackSnapshot().bufferFraction)
        var snapshot = TorrentPlaybackSnapshot(availablePieces: 2, requiredPieces: 4)
        XCTAssertEqual(snapshot.bufferFraction, 0.5)
        snapshot.availablePieces = 10
        XCTAssertEqual(snapshot.bufferFraction, 1)
    }

    @MainActor
    func testOldAttemptCannotOverwriteNewEngineOrResetItsProgressOnStop() {
        let monitor = TorrentPlaybackMonitor()
        let old = UUID(), current = UUID()
        monitor.begin(owner: old)
        monitor.begin(owner: current)
        let update = TorrentPlaybackSnapshot(stage: .initialBuffer, downloadBytesPerSecond: 1_024, availablePieces: 3, requiredPieces: 4)
        monitor.publish(update, owner: current)
        monitor.publish(TorrentPlaybackSnapshot(stage: .failed), owner: old)
        monitor.finish(owner: old, error: "Late old failure")
        XCTAssertEqual(monitor.snapshot, update)
        monitor.finish(owner: current)
        XCTAssertEqual(monitor.snapshot.stage, .stopped)
        monitor.publish(update, owner: current)
        XCTAssertEqual(monitor.snapshot.stage, .stopped)
    }

    func testBufferAndControlPreferencesHaveSafeDefaultsAndMeaningfulVariants() {
        XCTAssertEqual(TorrentPlaybackTuning.strategy("invalid"), .balanced)
        XCTAssertEqual(TorrentPlaybackTuning.strategy(nil).playerCacheMilliseconds, 1_500)
        XCTAssertLessThan(TorrentPlaybackTuning.BufferStrategy.quick.openingBytes, TorrentPlaybackTuning.BufferStrategy.resilient.openingBytes)
        XCTAssertEqual(TorrentPlaybackTuning.controlsDelay(0), 5)
        XCTAssertEqual(TorrentPlaybackTuning.controlsDelay(8), 8)
    }
}
