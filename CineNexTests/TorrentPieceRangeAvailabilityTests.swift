import XCTest
@testable import CineNex

final class TorrentPieceRangeAvailabilityTests: XCTestCase {
    private actor RecordingScheduler: TorrentPieceAvailabilityScheduling {
        private var recordedEvents: [String] = []

        func prioritize(pieces: Range<Int64>) async throws {
            recordedEvents.append("prioritize:\(pieces.lowerBound)-\(pieces.upperBound)")
        }

        func waitUntilAvailable(pieces: Range<Int64>) async throws {
            recordedEvents.append("wait:\(pieces.lowerBound)-\(pieces.upperBound)")
        }

        func events() -> [String] {
            recordedEvents
        }
    }

    func testPrioritizesMappedPiecesBeforeWaitingForAvailability() async throws {
        let scheduler = RecordingScheduler()
        let availability = try TorrentPieceRangeAvailability(
            fileStartOffset: 6,
            fileLength: 10,
            pieceLength: 4,
            scheduler: scheduler
        )

        try await availability.waitUntilAvailable(offset: 2, length: 4)

        let events = await scheduler.events()
        XCTAssertEqual(events, ["prioritize:2-3", "wait:2-3"])
    }

    func testZeroLengthRangeDoesNotSchedulePieces() async throws {
        let scheduler = RecordingScheduler()
        let availability = try TorrentPieceRangeAvailability(
            fileStartOffset: 3,
            fileLength: 8,
            pieceLength: 4,
            scheduler: scheduler
        )

        try await availability.waitUntilAvailable(offset: 4, length: 0)

        let events = await scheduler.events()
        XCTAssertTrue(events.isEmpty)
    }

    func testRejectsReadsOutsideSelectedFileBeforeScheduling() async throws {
        let scheduler = RecordingScheduler()
        let availability = try TorrentPieceRangeAvailability(
            fileStartOffset: 0,
            fileLength: 8,
            pieceLength: 4,
            scheduler: scheduler
        )

        do {
            try await availability.waitUntilAvailable(offset: 7, length: 2)
            XCTFail("A range beyond the selected file must be rejected.")
        } catch {
            XCTAssertEqual(error as? TorrentPieceRangePlannerError, .rangeOutsideFile)
        }

        let events = await scheduler.events()
        XCTAssertTrue(events.isEmpty)
    }

    func testRejectsInvalidTorrentLayout() {
        XCTAssertThrowsError(
            try TorrentPieceRangeAvailability(
                fileStartOffset: -1,
                fileLength: 8,
                pieceLength: 4,
                scheduler: RecordingScheduler()
            )
        ) { error in
            XCTAssertEqual(error as? TorrentPieceRangePlannerError, .invalidParameters)
        }
    }

    func testRejectsOverflowingTorrentLayout() {
        XCTAssertThrowsError(
            try TorrentPieceRangeAvailability(
                fileStartOffset: Int64.max,
                fileLength: 1,
                pieceLength: 4,
                scheduler: RecordingScheduler()
            )
        ) { error in
            XCTAssertEqual(error as? TorrentPieceRangePlannerError, .integerOverflow)
        }
    }
}
