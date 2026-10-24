import Foundation

enum TorrentHTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case head = "HEAD"
    case unsupported
}

struct TorrentHTTPResponsePlan: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let bodyRange: TorrentHTTPByteRange?
    let sendsBody: Bool

    static func make(
        method: String,
        rangeHeader: String?,
        totalLength: Int64,
        contentType: String
    ) -> TorrentHTTPResponsePlan {
        let normalizedMethod = method.uppercased()
        guard normalizedMethod == "GET" || normalizedMethod == "HEAD" else {
            return TorrentHTTPResponsePlan(
                statusCode: 405,
                headers: ["Allow": "GET, HEAD", "Content-Length": "0", "Connection": "close"],
                bodyRange: nil,
                sendsBody: false
            )
        }

        guard totalLength >= 0 else {
            return Self.error(statusCode: 500, headers: ["Content-Length": "0"])
        }

        do {
            let parsedRange = try TorrentHTTPByteRange.parse(rangeHeader, totalLength: totalLength)
            if let parsedRange {
                var headers = Self.baseHeaders(contentType: contentType)
                headers["Accept-Ranges"] = "bytes"
                headers["Content-Length"] = String(parsedRange.length)
                headers["Content-Range"] = "\(parsedRange.contentRangeValue)/\(totalLength)"
                headers["Connection"] = "close"
                return TorrentHTTPResponsePlan(
                    statusCode: 206,
                    headers: headers,
                    bodyRange: parsedRange,
                    sendsBody: normalizedMethod == "GET"
                )
            }

            var headers = Self.baseHeaders(contentType: contentType)
            headers["Accept-Ranges"] = "bytes"
            headers["Content-Length"] = String(totalLength)
            headers["Connection"] = "close"
            return TorrentHTTPResponsePlan(
                statusCode: 200,
                headers: headers,
                bodyRange: totalLength > 0 ? TorrentHTTPByteRange(lowerBound: 0, upperBound: totalLength - 1) : nil,
                sendsBody: normalizedMethod == "GET"
            )
        } catch TorrentHTTPByteRangeError.malformed {
            return Self.error(statusCode: 400, headers: ["Content-Length": "0"])
        } catch TorrentHTTPByteRangeError.unsatisfiable {
            return Self.error(
                statusCode: 416,
                headers: [
                    "Content-Range": "bytes */\(totalLength)",
                    "Content-Length": "0",
                    "Accept-Ranges": "bytes"
                ]
            )
        } catch {
            return Self.error(statusCode: 400, headers: ["Content-Length": "0"])
        }
    }

    private static func baseHeaders(contentType: String) -> [String: String] {
        let safeContentType = contentType.rangeOfCharacter(from: .newlines) == nil
            ? contentType
            : "application/octet-stream"
        return [
            "Content-Type": safeContentType,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff"
        ]
    }

    private static func error(statusCode: Int, headers: [String: String]) -> TorrentHTTPResponsePlan {
        TorrentHTTPResponsePlan(
            statusCode: statusCode,
            headers: headers.merging(["Connection": "close"]) { _, new in new },
            bodyRange: nil,
            sendsBody: false
        )
    }
}
