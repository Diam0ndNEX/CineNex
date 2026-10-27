import Foundation
import XCTest
@testable import CineNex

final class SourceDiscoveryNetworkingTests: XCTestCase {
    func testWallClockBudgetCancelsAnEndpointThatNeverReturnsHeaders() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourcePipelineURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let started = ContinuousClock.now
        do {
            _ = try await SourceDiscoveryNetworking.data(for: URLRequest(url: URL(string: "https://slow.example.test/stalled")!),
                                                        session: session, timeout: 0.05)
            XCTFail("A stalled connection must not wait for URLSession's resource timeout.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }

    func testManifestCachePersistsButExpiringPlaybackResponsesRemainMemoryOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = SourceDiscoveryCache(directory: directory)
        await cache.store(Data("manifest".utf8), for: "https://example.test/private-config/manifest.json", resource: .manifest, lifetime: 30, now: now)
        await cache.store(Data("signed-video-url".utf8), for: "stream-key", resource: .streams, lifetime: 30, now: now)
        let reopened = SourceDiscoveryCache(directory: directory)
        let manifest = await reopened.data(for: "https://example.test/private-config/manifest.json", resource: .manifest, now: now)
        let streams = await reopened.data(for: "stream-key", resource: .streams, now: now)
        let expired = await cache.data(for: "https://example.test/private-config/manifest.json", resource: .manifest, now: now.addingTimeInterval(31))
        XCTAssertEqual(manifest, Data("manifest".utf8))
        XCTAssertNil(streams)
        XCTAssertNil(expired)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.contains("private-config") })
    }

    func testExplicitRefreshClearsOnlyPlaybackResponses() async {
        let cache = SourceDiscoveryCache(directory: nil)
        await cache.store(Data("manifest".utf8), for: "manifest", resource: .manifest, lifetime: 30)
        await cache.store(Data("stream".utf8), for: "stream", resource: .streams, lifetime: 30)
        await cache.clearPlaybackResponses()
        let manifest = await cache.data(for: "manifest", resource: .manifest)
        let stream = await cache.data(for: "stream", resource: .streams)
        XCTAssertEqual(manifest, Data("manifest".utf8))
        XCTAssertNil(stream)
    }

    func testIdentifierLookupCoalescesAndReusesSuccessfulResult() async throws {
        let cache = SourceIdentifierCache(cache: SourceDiscoveryCache(directory: nil))
        let probe = SourceIdentifierProbe()
        let ids = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { try await cache.resolve(key: "same-title") { try await probe.lookup() } }
            }
            var ids: [String?] = []
            for try await id in group { ids.append(id) }
            return ids
        }
        XCTAssertEqual(ids.count, 20)
        XCTAssertTrue(ids.allSatisfy { $0 == "tt1234567" })
        let count = await probe.calls
        XCTAssertEqual(count, 1)
    }

    func testCancelledIdentifierWaiterCannotReuseAnOldProducer() async throws {
        let cache = SourceIdentifierCache(cache: SourceDiscoveryCache(directory: nil))
        let probe = SourceIdentifierProbe()
        let old = Task { try await cache.resolve(key: "same-title") { try await probe.lookup(delay: 5) } }
        for _ in 0..<100 {
            if await probe.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        old.cancel()
        do { _ = try await old.value; XCTFail("A cancelled waiter must throw.") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let replacement = try await cache.resolve(key: "same-title") { "tt7654321" }
        XCTAssertEqual(replacement, "tt7654321")
    }

    func testProgressiveProviderDeliversHealthyClientBeforeStalledClient() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourcePipelineURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = try StremioAddonPlaybackProvider(manifestURLs: [
            URL(string: "https://fast.example.test/manifest.json")!,
            URL(string: "https://slow.example.test/manifest.json")!
        ], externalIDResolver: PipelineIMDbResolver(), session: session)
        let updates = PipelineDiscoveryUpdates()
        let task = Task {
            try await provider.discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .movie),
                                        onUpdate: { await updates.append($0) })
        }
        for _ in 0..<200 {
            if await updates.first != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let first = await updates.first
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must stop the remaining request.") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(first?.sources.count, 1)
        XCTAssertEqual(first?.providerStatuses.count, 1, "A pending provider must not be reported as having no sources.")
        XCTAssertEqual(first?.sources.first?.url.absoluteString, "https://media.example.test/fast.mp4")
    }

    func testIdentifierUnavailableAndFailureAreDeliveredToProgressiveConsumer() async throws {
        for failing in [false, true] {
            let provider = try StremioAddonPlaybackProvider(manifestURLs: [URL(string: "https://fast.example.test/manifest.json")!],
                                                           externalIDResolver: UnavailablePipelineIMDbResolver(failing: failing))
            let updates = PipelineDiscoveryUpdates()
            let final = try await provider.discover(for: PlaybackSourceRequest(title: "Unknown", mediaKind: .movie),
                                                    onUpdate: { await updates.append($0) })
            let first = await updates.first
            XCTAssertEqual(first, final)
            XCTAssertEqual(first?.providerStatuses.count, 1)
            let outcome = try XCTUnwrap(first?.providerStatuses.first?.outcome)
            if !failing { XCTAssertEqual(outcome, .identifierUnavailable) }
            else {
                guard case .failed = outcome else { XCTFail("Expected identifier lookup failure."); continue }
            }
        }
    }

    func testNoStoreManifestAndStreamsAreNotRetainedInCustomCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourcePipelineURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = SourceDiscoveryCache(directory: nil)
        let client = try StremioAddonClient(manifestURL: URL(string: "https://no-store.example.test/manifest.json")!,
                                            session: session, cache: cache)
        let streams = try await client.fetchStreams(for: StremioStreamRequest(mediaType: "movie", itemID: "tt1234567"))
        XCTAssertEqual(streams.count, 1)
        let cachedManifest = await cache.data(for: "https://no-store.example.test/manifest.json", resource: .manifest)
        let cachedStreams = await cache.data(for: "https://no-store.example.test/stream/movie/tt1234567.json", resource: .streams)
        XCTAssertNil(cachedManifest)
        XCTAssertNil(cachedStreams)
    }

    func testTorrentioFallbackDoesNotWaitForStalledConfiguredEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourcePipelineURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let started = ContinuousClock.now
        let result = await SceneBoxTorrentSearch(sourceBases: ["https://slow.example.test", "https://fast.example.test"],
                                                 session: session, endpointTimeout: 3, fallbackDelay: 0.05)
            .discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .movie), externalIDResolver: PipelineIMDbResolver())
        XCTAssertEqual(result.sources.first?.url.absoluteString, "https://media.example.test/fast.mp4")
        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }
}

private actor SourceIdentifierProbe {
    private(set) var calls = 0
    func lookup(delay: Double = 0.05) async throws -> String? {
        calls += 1
        try await Task.sleep(for: .seconds(delay))
        return "tt1234567"
    }
}

private actor PipelineDiscoveryUpdates {
    private(set) var first: StremioAddonDiscovery?
    func append(_ value: StremioAddonDiscovery) { if first == nil { first = value } }
}

private struct UnavailablePipelineIMDbResolver: PlaybackExternalIDResolving {
    let failing: Bool
    func imdbID(for request: PlaybackSourceRequest) async throws -> String? {
        if failing { throw URLError(.timedOut) }
        return nil
    }
}

private struct PipelineIMDbResolver: PlaybackExternalIDResolving {
    func imdbID(for request: PlaybackSourceRequest) async throws -> String? { "tt1234567" }
}

private final class SourcePipelineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard ["fast.example.test", "no-store.example.test"].contains(request.url?.host ?? "") else { return }
        let manifest = #"{"id":"fast","version":"1","name":"Fast","resources":["stream"],"types":["movie"]}"#
        let streams = #"{"streams":[{"url":"https://media.example.test/fast.mp4"}]}"#
        let data = Data((request.url!.path.hasSuffix("manifest.json") ? manifest : streams).utf8)
        var headers = ["Content-Type": "application/json"]
        if request.url?.host == "no-store.example.test" { headers["Cache-Control"] = "private, no-store" }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
