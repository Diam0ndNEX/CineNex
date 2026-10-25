import Foundation

struct TorrentStreamTelemetrySnapshot: Equatable, Sendable {
    let requestCount: Int
    let rangeRequestCount: Int
    let bytesServed: Int64
    let failedRequestCount: Int
    let activeConnectionCount: Int
    let totalReadMilliseconds: Int64
    let maximumReadMilliseconds: Int64
}

final class TorrentStreamTelemetry: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var rangeRequestCount = 0
    private var bytesServed: Int64 = 0
    private var failedRequestCount = 0
    private var activeConnectionCount = 0
    private var totalReadMilliseconds: Int64 = 0
    private var maximumReadMilliseconds: Int64 = 0

    func recordRequest(isRange: Bool) {
        lock.withLock {
            requestCount = requestCount == Int.max ? Int.max : requestCount + 1
            if isRange {
                rangeRequestCount = rangeRequestCount == Int.max ? Int.max : rangeRequestCount + 1
            }
        }
    }

    func recordFailure() {
        lock.withLock {
            failedRequestCount = failedRequestCount == Int.max ? Int.max : failedRequestCount + 1
        }
    }

    func recordBytesServed(_ count: Int) {
        guard count > 0 else { return }
        lock.withLock {
            let (sum, overflow) = bytesServed.addingReportingOverflow(Int64(count))
            bytesServed = overflow ? Int64.max : sum
        }
    }

    func recordReadDuration(milliseconds: Int64) {
        let duration = max(0, milliseconds)
        lock.withLock {
            let (sum, overflow) = totalReadMilliseconds.addingReportingOverflow(duration)
            totalReadMilliseconds = overflow ? Int64.max : sum
            maximumReadMilliseconds = max(maximumReadMilliseconds, duration)
        }
    }

    func setActiveConnectionCount(_ count: Int) {
        lock.withLock {
            activeConnectionCount = max(0, count)
        }
    }

    func snapshot() -> TorrentStreamTelemetrySnapshot {
        lock.withLock {
            TorrentStreamTelemetrySnapshot(
                requestCount: requestCount,
                rangeRequestCount: rangeRequestCount,
                bytesServed: bytesServed,
                failedRequestCount: failedRequestCount,
                activeConnectionCount: activeConnectionCount,
                totalReadMilliseconds: totalReadMilliseconds,
                maximumReadMilliseconds: maximumReadMilliseconds
            )
        }
    }
}
