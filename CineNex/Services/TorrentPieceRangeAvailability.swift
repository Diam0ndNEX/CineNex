import Foundation

protocol TorrentPieceAvailabilityScheduling: Sendable {
    func prioritize(pieces: Range<Int64>) async throws
    func waitUntilAvailable(pieces: Range<Int64>) async throws
}

struct TorrentPieceRangeAvailability: TorrentRangeAvailability {
    let fileStartOffset: Int64
    let fileLength: Int64
    let pieceLength: Int64
    private let scheduler: any TorrentPieceAvailabilityScheduling

    init(
        fileStartOffset: Int64,
        fileLength: Int64,
        pieceLength: Int64,
        scheduler: any TorrentPieceAvailabilityScheduling
    ) throws {
        guard fileStartOffset >= 0, fileLength >= 0, pieceLength > 0 else {
            throw TorrentPieceRangePlannerError.invalidParameters
        }
        let (_, overflow) = fileStartOffset.addingReportingOverflow(fileLength)
        guard !overflow else {
            throw TorrentPieceRangePlannerError.integerOverflow
        }

        self.fileStartOffset = fileStartOffset
        self.fileLength = fileLength
        self.pieceLength = pieceLength
        self.scheduler = scheduler
    }

    func waitUntilAvailable(offset: Int64, length: Int64) async throws {
        try Task.checkCancellation()
        let pieces = try TorrentPieceRangePlanner.pieceRange(
            fileOffset: offset,
            byteCount: length,
            fileStartOffset: fileStartOffset,
            fileLength: fileLength,
            pieceLength: pieceLength
        )
        guard !pieces.isEmpty else { return }

        try await scheduler.prioritize(pieces: pieces)
        try Task.checkCancellation()
        try await scheduler.waitUntilAvailable(pieces: pieces)
        try Task.checkCancellation()
    }
}
