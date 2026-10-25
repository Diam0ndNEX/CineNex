import Foundation

protocol TorrentRangeAvailability: Sendable {
    func waitUntilAvailable(offset: Int64, length: Int64) async throws
}

enum TorrentDiskByteReaderError: LocalizedError, Equatable {
    case invalidRange
    case unavailableFile
    case shortRead(expected: Int, actual: Int)
    case closed

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "The requested torrent byte range is outside the selected file."
        case .unavailableFile:
            return "The selected torrent file is missing or larger than its expected size."
        case let .shortRead(expected, actual):
            return "The torrent file returned \(actual) bytes when \(expected) bytes were required."
        case .closed:
            return "The torrent byte reader is closed."
        }
    }
}

actor TorrentDiskByteReader: TorrentByteReader {
    let fileURL: URL
    let length: Int64

    private let fileHandle: FileHandle
    private let availability: any TorrentRangeAvailability
    private var isClosed = false
    private let readRetryDelays: [Duration] = [
        .milliseconds(40),
        .milliseconds(80),
        .milliseconds(120),
        .milliseconds(160),
        .milliseconds(200)
    ]

    init(
        fileURL: URL,
        expectedLength: Int64,
        availability: any TorrentRangeAvailability
    ) throws {
        guard expectedLength >= 0,
              FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let number = attributes[.size] as? NSNumber,
              number.int64Value <= expectedLength else {
            throw TorrentDiskByteReaderError.unavailableFile
        }
        self.fileURL = fileURL
        self.length = expectedLength
        self.availability = availability
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)
    }

    func read(offset: Int64, length requestedLength: Int) async throws -> Data {
        guard !isClosed else { throw TorrentDiskByteReaderError.closed }
        guard offset >= 0,
              requestedLength >= 0,
              offset <= length,
              Int64(requestedLength) <= length - offset else {
            throw TorrentDiskByteReaderError.invalidRange
        }
        guard requestedLength > 0 else { return Data() }

        try Task.checkCancellation()
        try await availability.waitUntilAvailable(
            offset: offset,
            length: Int64(requestedLength)
        )
        try Task.checkCancellation()
        guard !isClosed else { throw TorrentDiskByteReaderError.closed }

        var lastShortRead: TorrentDiskByteReaderError?
        for attempt in 0...readRetryDelays.count {
            try Task.checkCancellation()
            guard !isClosed else { throw TorrentDiskByteReaderError.closed }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let number = attributes[.size] as? NSNumber,
                  number.int64Value <= length else {
                throw TorrentDiskByteReaderError.unavailableFile
            }

            let fileSize = number.int64Value
            let availableLength = max(0, fileSize - offset)
            if availableLength < Int64(requestedLength) {
                lastShortRead = .shortRead(
                    expected: requestedLength,
                    actual: Int(min(Int64(requestedLength), availableLength))
                )
            } else {
                try fileHandle.seek(toOffset: UInt64(offset))
                let data = try fileHandle.read(upToCount: requestedLength) ?? Data()
                if data.count == requestedLength {
                    return data
                }
                lastShortRead = .shortRead(expected: requestedLength, actual: data.count)
            }

            guard attempt < readRetryDelays.count else { break }
            try await Task.sleep(for: readRetryDelays[attempt])
        }

        throw lastShortRead ?? TorrentDiskByteReaderError.shortRead(expected: requestedLength, actual: 0)
    }

    func close() throws {
        guard !isClosed else { return }
        isClosed = true
        try fileHandle.close()
    }
}
