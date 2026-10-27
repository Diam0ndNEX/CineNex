import XCTest
@testable import CineNex

final class SourceColdStartTests: XCTestCase {
    func testDeadlineDoesNotWaitForSuspendedFoundationCompletionQueue() async throws {
        let queue = OperationQueue()
        queue.isSuspended = true
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ColdStartURLProtocol.self]
        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: queue)
        defer { queue.isSuspended = false; session.invalidateAndCancel() }
        // A safety release also makes this a finite failing regression for the old task-group race.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { queue.isSuspended = false }
        let start = ContinuousClock.now
        do {
            _ = try await SourceDiscoveryNetworking.data(for: URLRequest(url: URL(string: "https://cold.example.test/manifest.json")!),
                                                        session: session, timeout: 0.05)
            XCTFail("Expected the wall-clock deadline")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(1.5))
    }

    @MainActor
    func testSlowSecureStorageDoesNotBlockUIAndTimesOutIndependently() async throws {
        let semaphore = DispatchSemaphore(value: 0)
        let loader = SourceSecureSettingsLoader {
            semaphore.wait()
            return SourceSecureSettings(manifestText: nil, tmdbToken: nil, manifestStorageUnavailable: false)
        }
        defer { semaphore.signal() }
        var uiTicked = false
        let tick = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(10))
            uiTicked = true
        }
        defer { tick.cancel() }
        let start = ContinuousClock.now
        do {
            _ = try await loader.load(timeout: 0.08)
            XCTFail("A secure-storage stall must release the screen to built-in providers")
        } catch is SourceSecureSettingsLoader.SettingsError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(uiTicked, "The UI actor must run while Security IPC is blocked")
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }

    func testCancelledSecureSettingsWaiterReturnsBeforeItsWorker() async throws {
        let semaphore = DispatchSemaphore(value: 0)
        let loader = SourceSecureSettingsLoader {
            semaphore.wait()
            return SourceSecureSettings(manifestText: nil, tmdbToken: nil, manifestStorageUnavailable: false)
        }
        defer { semaphore.signal() }
        let waiting = Task { try await loader.load(timeout: 5) }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        let start = ContinuousClock.now
        do { _ = try await waiting.value; XCTFail("Cancelled waiter must not remain attached to Security IPC") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }
}

private final class ColdStartURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { /* Intentionally never produces a transport completion. */ }
    override func stopLoading() { /* Cancellation completion must not gate the caller's deadline. */ }
}
