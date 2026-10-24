import XCTest
@testable import CineNex

final class TorrentHTTPRequestTests: XCTestCase {
    func testParsesGetAndNormalizesHeaderNames() throws {
        let request = try TorrentHTTPRequest.parse(Data("GET /v1/token/file HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=10-19\r\n\r\n".utf8))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.target, "/v1/token/file")
        XCTAssertEqual(request.headers["range"], "bytes=10-19")
    }

    func testRejectsDuplicateHeaders() {
        XCTAssertThrowsError(try TorrentHTTPRequest.parse(Data("GET /v1/a/b HTTP/1.1\r\nRange: bytes=0-1\r\nrange: bytes=2-3\r\n\r\n".utf8)))
    }

    func testRejectsTransferEncodingAndRequestBodies() {
        let requests = [
            "GET /v1/a/b HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "GET /v1/a/b HTTP/1.1\r\nContent-Length: 1\r\n\r\n",
            "GET /v1/a/b HTTP/1.1\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n"
        ]
        for value in requests {
            XCTAssertThrowsError(try TorrentHTTPRequest.parse(Data(value.utf8)))
        }
    }

    func testRejectsMalformedLinesAndAbsoluteTargets() {
        let requests = [
            "GET  /v1/a/b HTTP/1.1\r\n\r\n",
            "GET http://example.com/ HTTP/1.1\r\n\r\n",
            "GET /v1/a/b HTTP/2.0\r\n\r\n"
        ]
        for value in requests {
            XCTAssertThrowsError(try TorrentHTTPRequest.parse(Data(value.utf8)))
        }
    }

    func testRejectsOversizedHeaders() {
        let value = "GET /v1/a/b HTTP/1.1\r\nX-Test: " + String(repeating: "a", count: 17_000) + "\r\n\r\n"
        XCTAssertThrowsError(try TorrentHTTPRequest.parse(Data(value.utf8)))
    }

    func testRejectsBytesAfterHeaderTerminator() {
        XCTAssertThrowsError(try TorrentHTTPRequest.parse(Data("GET /v1/a/b HTTP/1.1\r\n\r\nbody".utf8)))
    }
}
