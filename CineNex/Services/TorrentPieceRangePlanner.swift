import Foundation

enum TorrentPieceRangePlannerError: Error, Equatable {
    case invalidParameters
    case rangeOutsideFile
    case integerOverflow
}

enum TorrentPieceRangePlanner {
    static func pieceRange(
        fileOffset: Int64,
        byteCount: Int64,
        fileStartOffset: Int64,
        fileLength: Int64,
        pieceLength: Int64
    ) throws -> Range<Int64> {
        guard fileOffset >= 0,
              byteCount >= 0,
              fileStartOffset >= 0,
              fileLength >= 0,
              pieceLength > 0 else {
            throw TorrentPieceRangePlannerError.invalidParameters
        }
        guard fileOffset <= fileLength,
              byteCount <= fileLength - fileOffset else {
            throw TorrentPieceRangePlannerError.rangeOutsideFile
        }

        let (_, fileEndOverflow) = fileStartOffset.addingReportingOverflow(fileLength)
        guard !fileEndOverflow else {
            throw TorrentPieceRangePlannerError.integerOverflow
        }

        let (globalStart, startOverflow) = fileStartOffset.addingReportingOverflow(fileOffset)
        guard !startOverflow else {
            throw TorrentPieceRangePlannerError.integerOverflow
        }

        let startPiece = globalStart / pieceLength
        guard byteCount > 0 else {
            return startPiece..<startPiece
        }

        let (globalEnd, endOverflow) = globalStart.addingReportingOverflow(byteCount)
        guard !endOverflow, globalEnd > 0 else {
            throw TorrentPieceRangePlannerError.integerOverflow
        }

        let lastPiece = (globalEnd - 1) / pieceLength
        let (exclusiveEnd, pieceOverflow) = lastPiece.addingReportingOverflow(1)
        guard !pieceOverflow else {
            throw TorrentPieceRangePlannerError.integerOverflow
        }
        return startPiece..<exclusiveEnd
    }
}
