import XCTest
@testable import CineNex

final class TorrentHTTPResponsePlanTests: XCTestCase {
    func testGetWithoutRangeReturnsWholeResource() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "GET",
            rangeHeader: nil,
            totalLength: 128,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 200)
        XCTAssertEqual(plan.headers["Content-Length"], "128")
        XCTAssertEqual(plan.headers["Accept-Ranges"], "bytes")
        XCTAssertEqual(plan.headers["Content-Type"], "video/mp4")
        XCTAssertEqual(plan.bodyRange, TorrentHTTPByteRange(lowerBound: 0, upperBound: 127))
        XCTAssertTrue(plan.sendsBody)
    }

    func testGetWithRangeReturnsPartialContentHeaders() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "GET",
            rangeHeader: "bytes=32-63",
            totalLength: 128,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 206)
        XCTAssertEqual(plan.headers["Content-Length"], "32")
        XCTAssertEqual(plan.headers["Content-Range"], "bytes 32-63/128")
        XCTAssertEqual(plan.bodyRange, TorrentHTTPByteRange(lowerBound: 32, upperBound: 63))
        XCTAssertTrue(plan.sendsBody)
    }

    func testHeadIgnoresRangeAndReturnsFullResourceMetadataWithoutBody() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "HEAD",
            rangeHeader: "bytes=10-19",
            totalLength: 100,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 200)
        XCTAssertEqual(plan.headers["Content-Length"], "100")
        XCTAssertNil(plan.headers["Content-Range"])
        XCTAssertFalse(plan.sendsBody)
    }

    func testHeadIgnoresMalformedRangeHeader() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "HEAD",
            rangeHeader: "bytes=malformed",
            totalLength: 50,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 200)
        XCTAssertEqual(plan.headers["Content-Length"], "50")
        XCTAssertFalse(plan.sendsBody)
    }

    func testMalformedRangeMapsToBadRequest() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "GET",
            rangeHeader: "bytes=1-2,4-5",
            totalLength: 100,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 400)
        XCTAssertEqual(plan.headers["Content-Length"], "0")
        XCTAssertNil(plan.bodyRange)
        XCTAssertFalse(plan.sendsBody)
    }

    func testUnsatisfiableRangeMapsToRangeNotSatisfiable() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "GET",
            rangeHeader: "bytes=100-",
            totalLength: 100,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 416)
        XCTAssertEqual(plan.headers["Content-Range"], "bytes */100")
        XCTAssertNil(plan.bodyRange)
    }

    func testUnsupportedMethodIsRejectedAndAdvertisesAllowedMethods() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "POST",
            rangeHeader: nil,
            totalLength: 100,
            contentType: "video/mp4"
        )

        XCTAssertEqual(plan.statusCode, 405)
        XCTAssertEqual(plan.headers["Allow"], "GET, HEAD")
        XCTAssertFalse(plan.sendsBody)
    }

    func testInvalidContentTypeCannotInjectResponseHeaders() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "GET",
            rangeHeader: nil,
            totalLength: 5,
            contentType: "video/mp4\r\nX-Injected: yes"
        )

        XCTAssertEqual(plan.headers["Content-Type"], "application/octet-stream")
        XCTAssertNil(plan.headers["X-Injected"])
    }

    func testEmptyResourceProducesZeroLengthFullResponse() {
        let plan = TorrentHTTPResponsePlan.make(
            method: "GET",
            rangeHeader: nil,
            totalLength: 0,
            contentType: "application/octet-stream"
        )

        XCTAssertEqual(plan.statusCode, 200)
        XCTAssertEqual(plan.headers["Content-Length"], "0")
        XCTAssertNil(plan.bodyRange)
    }
}
