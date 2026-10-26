import XCTest
@testable import CineNex

final class SmartPlaybackSelectionTests: XCTestCase {
    private func source(_ id: String) -> PlaybackSource {
        PlaybackSource(id: id, providerID: "fixture", providerName: "Fixture", title: id,
                       url: URL(string: "https://video.example.test/\(id).mp4")!, qualityLabel: nil,
                       languageCode: nil, subtitleLanguages: [], supportsNativePlayback: true, providerPriority: 1)
    }

    func testSmartSelectionDeduplicatesSameTorrentAcrossProvidersAndKeepsUnknownMetadata() throws {
        let first = try XCTUnwrap(StremioTorrentDescriptor(infoHash: String(repeating: "a", count: 40), fileIndex: 0,
                                    title: "1080p", providerName: "Torrentio", seeders: 20, videoSize: 8_000_000_000))
        let duplicate = try XCTUnwrap(StremioTorrentDescriptor(infoHash: first.infoHash, fileIndex: 0,
                                    title: "1080p", providerName: "MediaFusion", seeders: 20, videoSize: 8_000_000_000))
        let unknown = try XCTUnwrap(StremioTorrentDescriptor(infoHash: String(repeating: "b", count: 40), fileIndex: 0))
        let dead = try XCTUnwrap(StremioTorrentDescriptor(infoHash: String(repeating: "c", count: 40), fileIndex: 0, seeders: 0))
        let all = SmartPlaybackSelection.candidates(torrents: [dead, unknown, first, duplicate], direct: [])
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.last?.id, SmartPlaybackCandidate.torrent(dead).id)
        let filtered = SmartPlaybackSelection.candidates(torrents: [first, unknown, dead], direct: [],
                                                         maximumBytes: 5_000_000_000, hidingKnownDead: true)
        XCTAssertEqual(filtered.map(\.id), [SmartPlaybackCandidate.torrent(unknown).id])
    }

    @MainActor
    func testFailedPreparationFallsThroughAndStopsAfterFirstReadySource() async throws {
        let candidates = [SmartPlaybackCandidate.direct(source("bad")), .direct(source("ready")), .direct(source("unused"))]
        var attempted: [String] = []
        var failures: [String] = []
        let result = try await SmartPlaybackSelection.firstReady(candidates: candidates, maximumAttempts: 3,
            onAttempt: { candidate, _, _ in attempted.append(candidate.id) },
            onFailure: { candidate, _ in failures.append(candidate.id) }, prepare: { candidate in
                if candidate.id == candidates[0].id { throw URLError(.cannotConnectToHost) }
                guard case .direct(let source) = candidate else { throw URLError(.unknown) }
                return source
            })
        XCTAssertEqual(result.id, "ready")
        XCTAssertEqual(attempted, Array(candidates.prefix(2)).map(\.id))
        XCTAssertEqual(failures, [candidates[0].id])
    }

    @MainActor
    func testCancellationNeverTriesNextSource() async {
        var attempts = 0
        do {
            _ = try await SmartPlaybackSelection.firstReady(candidates: [.direct(source("one")), .direct(source("two"))],
                maximumAttempts: 3, onAttempt: { _, _, _ in attempts += 1 }, onFailure: { _, _ in XCTFail("Cancellation isn't a failed release") },
                prepare: { _ in throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    func testAttemptLimitBoundsUnreachableReleaseWork() async {
        let choices = (0..<8).map { SmartPlaybackCandidate.direct(source("source-\($0)")) }
        var attempts = 0
        do {
            _ = try await SmartPlaybackSelection.firstReady(candidates: choices, maximumAttempts: 99,
                onAttempt: { _, _, _ in attempts += 1 }, onFailure: { _, _ in },
                prepare: { _ in throw URLError(.timedOut) })
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(attempts, 5) }
    }

    @MainActor
    func testCancellationAfterReadinessDiscardsPreparedSession() async {
        let ready = source("ready")
        var discarded: [String] = []
        let task = Task { @MainActor in
            try await SmartPlaybackSelection.firstReady(candidates: [.direct(ready)], maximumAttempts: 1,
                onAttempt: { _, _, _ in }, onFailure: { _, _ in XCTFail("Cancellation must not be treated as release failure") },
                discard: { discarded.append($0.id) }, prepare: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return ready
                })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(discarded, [ready.id])
    }

    func testDirectReadinessRejectsHTMLAndUsesHeadWithoutDownloadingVideo() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadinessURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ReadinessURLProtocol.requests.handler = nil }
        let candidate = source("movie")
        ReadinessURLProtocol.requests.handler = { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "text/html"])!, Data())
        }
        do { _ = try await DirectPlaybackReadinessProbe(session: session).confirm(candidate); XCTFail("HTML must not count as video readiness") }
        catch { }
        ReadinessURLProtocol.requests.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                             headerFields: ["Content-Type": "video/mp4"])!, Data())
        }
        let ready = try await DirectPlaybackReadinessProbe(session: session).confirm(candidate)
        XCTAssertEqual(ready, candidate)
    }
}

private final class ReadinessURLProtocol: URLProtocol {
    static let requests = LockedURLRequestHandler()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.requests.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
