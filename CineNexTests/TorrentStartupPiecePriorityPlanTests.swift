import XCTest
@testable import CineNex

final class TorrentStartupPiecePriorityPlanTests: XCTestCase {
    func testPrioritizesSelectedFileHeadAndTailUsingGlobalPieceOffsets() throws {
        let plan = try XCTUnwrap(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: 10,
            fileLength: 30,
            pieceLength: 4,
            pieceCount: 20,
            headBytes: 4,
            tailBytes: 4,
            headPriority: 7,
            tailPriority: 5
        ))

        XCTAssertEqual(plan.priorities, [2: 7, 3: 7, 9: 5])
    }

    func testHeadPriorityWinsWhenHeadAndTailOverlap() throws {
        let plan = try XCTUnwrap(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: 0,
            fileLength: 8,
            pieceLength: 4,
            pieceCount: 2,
            headBytes: 8,
            tailBytes: 8,
            headPriority: 7,
            tailPriority: 5
        ))

        XCTAssertEqual(plan.priorities, [0: 7, 1: 7])
    }

    func testSmallFilePrioritizesOnlyItsActualPieces() throws {
        let plan = try XCTUnwrap(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: 5,
            fileLength: 3,
            pieceLength: 4,
            pieceCount: 3,
            headBytes: 2,
            tailBytes: 2
        ))

        XCTAssertEqual(plan.priorities, [1: 7])
    }

    func testEmptyFileProducesNoStartupPriorities() throws {
        let plan = try XCTUnwrap(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: 8,
            fileLength: 0,
            pieceLength: 4,
            pieceCount: 2
        ))

        XCTAssertTrue(plan.priorities.isEmpty)
    }

    func testRejectsInvalidCoordinatesAndOverflow() {
        XCTAssertNil(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: -1,
            fileLength: 4,
            pieceLength: 4,
            pieceCount: 2
        ))
        XCTAssertNil(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: 0,
            fileLength: 4,
            pieceLength: 0,
            pieceCount: 2
        ))
        XCTAssertNil(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: 4,
            fileLength: 4,
            pieceLength: 4,
            pieceCount: 1
        ))
        XCTAssertNil(TorrentStartupPiecePriorityPlan.make(
            fileStartOffset: Int64.max,
            fileLength: 1,
            pieceLength: 4,
            pieceCount: 2
        ))
    }
}
