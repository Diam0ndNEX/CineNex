import XCTest
@testable import CineNex

final class TorrentPieceRangePlannerTests: XCTestCase {
    func testRangeSpanningSeveralPiecesUsesHalfOpenPieceIndices() throws {
        let pieces = try TorrentPieceRangePlanner.pieceRange(
            fileOffset: 3,
            byteCount: 6,
            fileStartOffset: 0,
            fileLength: 20,
            pieceLength: 4
        )

        XCTAssertEqual(pieces, 0..<3)
    }

    func testFileOffsetAccountsForPiecesSharedWithPreviousFiles() throws {
        let pieces = try TorrentPieceRangePlanner.pieceRange(
            fileOffset: 2,
            byteCount: 4,
            fileStartOffset: 6,
            fileLength: 10,
            pieceLength: 4
        )

        XCTAssertEqual(pieces, 2..<3)
    }

    func testRangeEndingExactlyAtPieceBoundaryDoesNotIncludeNextPiece() throws {
        let pieces = try TorrentPieceRangePlanner.pieceRange(
            fileOffset: 4,
            byteCount: 4,
            fileStartOffset: 0,
            fileLength: 8,
            pieceLength: 4
        )

        XCTAssertEqual(pieces, 1..<2)
    }

    func testZeroLengthRangeReturnsAnEmptyPieceRange() throws {
        let pieces = try TorrentPieceRangePlanner.pieceRange(
            fileOffset: 4,
            byteCount: 0,
            fileStartOffset: 3,
            fileLength: 8,
            pieceLength: 4
        )

        XCTAssertEqual(pieces, 1..<1)
    }

    func testRejectsRangeOutsideSelectedFile() {
        XCTAssertThrowsError(
            try TorrentPieceRangePlanner.pieceRange(
                fileOffset: 8,
                byteCount: 1,
                fileStartOffset: 0,
                fileLength: 8,
                pieceLength: 4
            )
        ) { error in
            XCTAssertEqual(error as? TorrentPieceRangePlannerError, .rangeOutsideFile)
        }
    }

    func testRejectsInvalidPieceLength() {
        XCTAssertThrowsError(
            try TorrentPieceRangePlanner.pieceRange(
                fileOffset: 0,
                byteCount: 1,
                fileStartOffset: 0,
                fileLength: 8,
                pieceLength: 0
            )
        ) { error in
            XCTAssertEqual(error as? TorrentPieceRangePlannerError, .invalidParameters)
        }
    }

    func testRejectsOverflowInTorrentFileCoordinates() {
        XCTAssertThrowsError(
            try TorrentPieceRangePlanner.pieceRange(
                fileOffset: 0,
                byteCount: 1,
                fileStartOffset: Int64.max,
                fileLength: 1,
                pieceLength: 4
            )
        ) { error in
            XCTAssertEqual(error as? TorrentPieceRangePlannerError, .integerOverflow)
        }
    }

    func testInitialPriorityWindowPromotesAllRequestedPieces() {
        let window = TorrentPiecePriorityWindow(current: [], requested: [4, 5, 6])

        XCTAssertEqual(window.piecesToDemote, [])
        XCTAssertEqual(window.piecesToPromote, [4, 5, 6])
    }

    func testMovingPriorityWindowDemotesStalePiecesAndPromotesNewPieces() {
        let window = TorrentPiecePriorityWindow(current: [4, 5, 6], requested: [6, 7, 8])

        XCTAssertEqual(window.piecesToDemote, [4, 5])
        XCTAssertEqual(window.piecesToPromote, [7, 8])
    }

    func testUnchangedPriorityWindowDoesNotRepeatUpdates() {
        let window = TorrentPiecePriorityWindow(current: [4, 5, 6], requested: [4, 5, 6])

        XCTAssertEqual(window.piecesToDemote, [])
        XCTAssertEqual(window.piecesToPromote, [])
    }

    func testOverlappingPriorityWindowOnlyChangesTheDifference() {
        let window = TorrentPiecePriorityWindow(current: [10, 11, 12, 13], requested: [12, 13, 14, 15])

        XCTAssertEqual(window.piecesToDemote, [10, 11])
        XCTAssertEqual(window.piecesToPromote, [14, 15])
    }

}
