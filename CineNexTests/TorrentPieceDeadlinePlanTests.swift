import XCTest
@testable import CineNex

final class TorrentPieceDeadlinePlanTests: XCTestCase {
    func testAssignsIncreasingDeadlinesInPlaybackOrder() throws {
        let plan = try XCTUnwrap(TorrentPieceDeadlinePlan.make(for: 20..<24, pieceCount: 100))

        XCTAssertEqual(plan.deadlinesMilliseconds, [20: 0, 21: 80, 22: 160, 23: 240])
    }

    func testDeadlinePlanCapsLongRangesAtMaximumDelay() throws {
        let plan = try XCTUnwrap(TorrentPieceDeadlinePlan.make(
            for: 0..<5,
            pieceCount: 5,
            stepMilliseconds: 100,
            maximumMilliseconds: 150
        ))

        XCTAssertEqual(plan.deadlinesMilliseconds, [0: 0, 1: 100, 2: 150, 3: 150, 4: 150])
    }

    func testLargeStepSaturatesWithoutIntegerOverflow() throws {
        let plan = try XCTUnwrap(TorrentPieceDeadlinePlan.make(
            for: 0..<3,
            pieceCount: 3,
            stepMilliseconds: Int.max,
            maximumMilliseconds: 60_000
        ))

        XCTAssertEqual(plan.deadlinesMilliseconds, [0: 0, 1: 60_000, 2: 60_000])
    }

    func testEmptyRangeProducesNoDeadlines() throws {
        let plan = try XCTUnwrap(TorrentPieceDeadlinePlan.make(for: 3..<3, pieceCount: 10))

        XCTAssertTrue(plan.deadlinesMilliseconds.isEmpty)
    }

    func testRejectsOutOfBoundsRangesAndInvalidDelays() {
        XCTAssertNil(TorrentPieceDeadlinePlan.make(for: -1..<2, pieceCount: 10))
        XCTAssertNil(TorrentPieceDeadlinePlan.make(for: 4..<11, pieceCount: 10))
        XCTAssertNil(TorrentPieceDeadlinePlan.make(for: 0..<1, pieceCount: -1))
        XCTAssertNil(TorrentPieceDeadlinePlan.make(for: 0..<1, pieceCount: 10, stepMilliseconds: -1))
        XCTAssertNil(TorrentPieceDeadlinePlan.make(for: 0..<1, pieceCount: 10, maximumMilliseconds: -1))
    }
}
