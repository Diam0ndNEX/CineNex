import XCTest
@testable import CineNex

final class TorrentHTTPByteRangeTests: XCTestCase {
    func testMissingHeaderRequestsWholeResource() throws {
        XCTAssertNil(try TorrentHTTPByteRange.parse(nil, totalLength: 100))
    }

    func testClosedRangePreservesInclusiveBounds() throws {
        let range = try XCTUnwrap(TorrentHTTPByteRange.parse("bytes=10-19", totalLength: 100))
        XCTAssertEqual(range, TorrentHTTPByteRange(lowerBound: 10, upperBound: 19))
        XCTAssertEqual(range.length, 10)
        XCTAssertEqual(range.contentRangeValue, "bytes 10-19")
    }

    func testOpenEndedRangeRunsToEndOfResource() throws {
        let range = try XCTUnwrap(TorrentHTTPByteRange.parse("bytes=90-", totalLength: 100))
        XCTAssertEqual(range, TorrentHTTPByteRange(lowerBound: 90, upperBound: 99))
        XCTAssertEqual(range.length, 10)
    }

    func testSuffixRangeSelectsLastBytes() throws {
        let range = try XCTUnwrap(TorrentHTTPByteRange.parse("bytes=-12", totalLength: 100))
        XCTAssertEqual(range, TorrentHTTPByteRange(lowerBound: 88, upperBound: 99))
    }

    func testSuffixLongerThanResourceSelectsWholeResource() throws {
        let range = try XCTUnwrap(TorrentHTTPByteRange.parse("bytes=-200", totalLength: 100))
        XCTAssertEqual(range, TorrentHTTPByteRange(lowerBound: 0, upperBound: 99))
    }

    func testEndBeyondResourceIsClamped() throws {
        let range = try XCTUnwrap(TorrentHTTPByteRange.parse("bytes=80-500", totalLength: 100))
        XCTAssertEqual(range, TorrentHTTPByteRange(lowerBound: 80, upperBound: 99))
    }

    func testUnitIsCaseInsensitiveAndOuterWhitespaceIsIgnored() throws {
        let range = try XCTUnwrap(TorrentHTTPByteRange.parse("  BYTES=2-4\n", totalLength: 8))
        XCTAssertEqual(range, TorrentHTTPByteRange(lowerBound: 2, upperBound: 4))
    }

    func testRejectsMultipleRangesBecauseServerDoesNotImplementMultipartRanges() {
        XCTAssertThrowsError(try TorrentHTTPByteRange.parse("bytes=0-2,5-8", totalLength: 10)) {
            XCTAssertEqual($0 as? TorrentHTTPByteRangeError, .malformed)
        }
    }

    func testRejectsInvalidSyntax() {
        let invalidHeaders = ["items=0-1", "bytes=", "bytes=-", "bytes=--1", "bytes=1-2-3", "bytes=1 -2", "bytes=abc-4"]
        for header in invalidHeaders {
            XCTAssertThrowsError(try TorrentHTTPByteRange.parse(header, totalLength: 10), header)
        }
    }

    func testRejectsUnsatisfiableRanges() {
        let invalidHeaders = ["bytes=10-10", "bytes=9-2", "bytes=-0", "bytes=0-1"]
        for header in invalidHeaders {
            XCTAssertThrowsError(try TorrentHTTPByteRange.parse(header, totalLength: 10), header)
        }
    }

    func testRejectsEmptyResourceRanges() {
        XCTAssertThrowsError(try TorrentHTTPByteRange.parse("bytes=0-", totalLength: 0)) {
            XCTAssertEqual($0 as? TorrentHTTPByteRangeError, .unsatisfiable)
        }
    }

    func testRejectsNegativeTotalLength() {
        XCTAssertThrowsError(try TorrentHTTPByteRange.parse(nil, totalLength: -1)) {
            XCTAssertEqual($0 as? TorrentHTTPByteRangeError, .unsatisfiable)
        }
    }

    func testRejectsIntegerOverflow() {
        XCTAssertThrowsError(try TorrentHTTPByteRange.parse("bytes=999999999999999999999999999999-", totalLength: 100))
    }
}
