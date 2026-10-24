import Foundation
import XCTest
@testable import CineNex

final class TorrentDiskByteReaderTests: XCTestCase {
    private actor ImmediateAvailability: TorrentRangeAvailability {
        private(set) var requestedRanges: [(Int64, Int64)] = []

        func waitUntilAvailable(offset: Int64, length: Int64) async throws {
            requestedRanges.append((offset, length))
        }

        func ranges() -> [(Int64, Int64)] {
            requestedRanges
        }
    }

    private actor SlowAvailability: TorrentRangeAvailability {
        func waitUntilAvailable(offset: Int64, length: Int64) async throws {
            try await Task.sleep(for: .seconds(30))
        }
    }

    private actor DelayedAvailability: TorrentRangeAvailability {
        private var continuation: CheckedContinuation<Void, Error>?
        private var hasBeenReleased = false

        func waitUntilAvailable(offset: Int64, length: Int64) async throws {
            if hasBeenReleased { return }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release() {
            hasBeenReleased = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func makeTemporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinenex-torrent-reader-\(UUID().uuidString).bin")
        try data.write(to: url, options: .atomic)
        return url
    }

    func testReadsExactBytesAtRequestedOffsetOnlyAfterAvailability() async throws {
        let expected = Data("0123456789abcdef".utf8)
        let url = try makeTemporaryFile(expected)
        defer { try? FileManager.default.removeItem(at: url) }
        let availability = ImmediateAvailability()
        let reader = try TorrentDiskByteReader(
            fileURL: url,
            expectedLength: Int64(expected.count),
            availability: availability
        )

        let data = try await reader.read(offset: 5, length: 4)

        XCTAssertEqual(data, Data("5678".utf8))
        let ranges = await availability.ranges()
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.0, 5)
        XCTAssertEqual(ranges.first?.1, 4)
        try await reader.close()
    }

    func testReadWaitsUntilRequestedRangeIsAvailable() async throws {
        let expected = Data("streamable".utf8)
        let url = try makeTemporaryFile(expected)
        defer { try? FileManager.default.removeItem(at: url) }
        let availability = DelayedAvailability()
        let reader = try TorrentDiskByteReader(
            fileURL: url,
            expectedLength: Int64(expected.count),
            availability: availability
        )

        let readTask = Task { try await reader.read(offset: 0, length: 6) }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(readTask.isCancelled)
        await availability.release()
        let readData = try await readTask.value
        XCTAssertEqual(readData, Data("stream".utf8))
        try await reader.close()
    }

    func testRejectsNegativeAndOutOfBoundsRanges() async throws {
        let url = try makeTemporaryFile(Data("12345".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try TorrentDiskByteReader(
            fileURL: url,
            expectedLength: 5,
            availability: ImmediateAvailability()
        )

        do {
            _ = try await reader.read(offset: -1, length: 1)
            XCTFail("A negative offset must be rejected.")
        } catch {
            XCTAssertEqual(error as? TorrentDiskByteReaderError, .invalidRange)
        }

        do {
            _ = try await reader.read(offset: 4, length: 2)
            XCTFail("A range extending past EOF must be rejected.")
        } catch {
            XCTAssertEqual(error as? TorrentDiskByteReaderError, .invalidRange)
        }
        try await reader.close()
    }

    func testRejectsFileWhoseSizeDoesNotMatchExpectedLength() throws {
        let url = try makeTemporaryFile(Data("short".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(
            try TorrentDiskByteReader(
                fileURL: url,
                expectedLength: 99,
                availability: ImmediateAvailability()
            )
        ) {
            XCTAssertEqual($0 as? TorrentDiskByteReaderError, .unavailableFile)
        }
    }

 
    func testCancellationWhileWaitingForBytesPropagates() async throws {
        let url = try makeTemporaryFile(Data("cancel".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try TorrentDiskByteReader(
            fileURL: url,
            expectedLength: 6,
            availability: SlowAvailability()
        )
        let readTask = Task { try await reader.read(offset: 0, length: 4) }
        try await Task.sleep(for: .milliseconds(40))
        readTask.cancel()
        do {
            _ = try await readTask.value
            XCTFail("A cancelled availability wait must not return bytes.")
        } catch is CancellationError {
            XCTAssertTrue(true)
        }
        try await reader.close()
    }

    func testShortReadFailsInsteadOfReturningIncompleteData() async throws {
        let url = try makeTemporaryFile(Data("complete".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try TorrentDiskByteReader(
            fileURL: url,
            expectedLength: 8,
            availability: ImmediateAvailability()
        )
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: 3)
        try writer.close()
        do {
            _ = try await reader.read(offset: 0, length: 8)
            XCTFail("A short disk read must fail.")
        } catch {
            XCTAssertEqual(error as? TorrentDiskByteReaderError, .shortRead(expected: 8, actual: 3))
        }
        try await reader.close()
    }

    func testClosedReaderRejectsFurtherReads() async throws {
        let url = try makeTemporaryFile(Data("close".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try TorrentDiskByteReader(
            fileURL: url,
            expectedLength: 5,
            availability: ImmediateAvailability()
        )
        try await reader.close()
        do {
            _ = try await reader.read(offset: 0, length: 1)
            XCTFail("A closed reader must reject reads.")
        } catch {
            XCTAssertEqual(error as? TorrentDiskByteReaderError, .closed)
        }
    }
}
