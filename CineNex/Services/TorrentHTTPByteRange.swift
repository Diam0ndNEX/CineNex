import Foundation

enum TorrentHTTPByteRangeError: Error, Equatable, Sendable {
    case malformed
    case unsatisfiable
}

struct TorrentHTTPByteRange: Equatable, Sendable {
    let lowerBound: Int64
    let upperBound: Int64

    var length: Int64 {
        upperBound - lowerBound + 1
    }

    var contentRangeValue: String {
        "bytes \(lowerBound)-\(upperBound)"
    }

    static func parse(_ headerValue: String?, totalLength: Int64) throws -> TorrentHTTPByteRange? {
        guard totalLength >= 0 else {
            throw TorrentHTTPByteRangeError.unsatisfiable
        }

        guard let headerValue else {
            return nil
        }

        let header = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = header.firstIndex(of: "=") else {
            throw TorrentHTTPByteRangeError.malformed
        }

        let unit = header[..<separator]
        let rawValue = header[header.index(after: separator)...]
        guard String(unit).caseInsensitiveCompare("bytes") == .orderedSame,
              !rawValue.isEmpty,
              !rawValue.contains(","),
              let dash = rawValue.firstIndex(of: "-"),
              rawValue[rawValue.index(after: dash)...].contains("-") == false else {
            throw TorrentHTTPByteRangeError.malformed
        }

        let rawStart = rawValue[..<dash]
        let rawEnd = rawValue[rawValue.index(after: dash)...]

        guard !rawStart.isEmpty || !rawEnd.isEmpty else {
            throw TorrentHTTPByteRangeError.malformed
        }

        guard totalLength > 0 else {
            throw TorrentHTTPByteRangeError.unsatisfiable
        }

        if rawStart.isEmpty {
            guard let suffixLength = parseUnsignedInteger(rawEnd), suffixLength > 0 else {
                throw TorrentHTTPByteRangeError.unsatisfiable
            }
            let selectedLength = min(suffixLength, UInt64(totalLength))
            return TorrentHTTPByteRange(
                lowerBound: totalLength - Int64(selectedLength),
                upperBound: totalLength - 1
            )
        }

        guard let start = parseUnsignedInteger(rawStart), start < UInt64(totalLength) else {
            throw TorrentHTTPByteRangeError.unsatisfiable
        }

        let end: Int64
        if rawEnd.isEmpty {
            end = totalLength - 1
        } else {
            guard let requestedEnd = parseUnsignedInteger(rawEnd), requestedEnd >= start else {
                throw TorrentHTTPByteRangeError.unsatisfiable
            }
            end = Int64(min(requestedEnd, UInt64(totalLength - 1)))
        }

        return TorrentHTTPByteRange(lowerBound: Int64(start), upperBound: end)
    }

    private static func parseUnsignedInteger<S: StringProtocol>(_ value: S) -> UInt64? {
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }
        return UInt64(value)
    }
}
