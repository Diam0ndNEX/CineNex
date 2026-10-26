import Foundation
import XCTest
@testable import CineNex

final class StremioAddonPlaybackProviderTests: XCTestCase {
    func testKnownIMDbIDIsUsedWithoutAnotherCatalogRequest() async throws {
        ProviderStubURLProtocol.handler = { _ in
            XCTFail("A valid IMDb ID already present on the title should not trigger another lookup.")
            throw URLError(.badServerResponse)
        }
        let resolver = CinemetaExternalIDResolver(session: makeSession())
        let id = try await resolver.imdbID(
            for: PlaybackSourceRequest(
                title: "Example Film",
                mediaKind: .movie,
                imdbID: "tt1234567"
            )
        )
        XCTAssertEqual(id, "tt1234567")
    }

    func testUsesExistingIMDbIDBeforeTitleLookup() async throws {
        ProviderStubURLProtocol.handler = { _ in
            XCTFail("A valid IMDb ID should be used directly without a network lookup.")
            throw URLError(.badServerResponse)
        }
        let resolver = CinemetaExternalIDResolver(session: makeSession())
        let result = try await resolver.imdbID(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, imdbID: "tt1234567")
        )
        XCTAssertEqual(result, "tt1234567")
    }

    func testCinemetaResolverFindsExactTitleWithoutTMDBToken() async throws {
        ProviderStubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "v3-cinemeta.strem.io")
            XCTAssertTrue(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath.hasSuffix("/search=Example%20Film.json") == true)
            let payload = #"{"metas":[{"imdb_id":"tt1111111","type":"movie","name":"Different Film","releaseInfo":"2024"},{"imdb_id":"tt1234567","type":"movie","name":"Example Film","releaseInfo":"2024"}]}"#
            return (self.response(request, 200), Data(payload.utf8))
        }
        let resolver = AutomaticExternalIDResolver(tmdbReadAccessToken: nil, session: makeSession())

        let id = try await resolver.imdbID(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, releaseYear: 2024)
        )

        XCTAssertEqual(id, "tt1234567")
    }

    func testCinemetaResolverRejectsSameTitleWithWrongYear() async throws {
        ProviderStubURLProtocol.handler = { request in
            let payload = #"{"metas":[{"id":"tt1234567","type":"movie","name":"Example Film","releaseInfo":"2018"}]}"#
            return (self.response(request, 200), Data(payload.utf8))
        }
        let resolver = CinemetaExternalIDResolver(session: makeSession())

        let id = try await resolver.imdbID(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, releaseYear: 2024)
        )

        XCTAssertNil(id)
    }

    func testCancelledProviderRequestStopsBeforeExternalNetworking() async {
        let provider = try! StremioAddonPlaybackProvider(
            manifestURLs: [
                URL(string: "https://addons.example.test/first/manifest.json")!,
                URL(string: "https://addons.example.test/second/manifest.json")!
            ],
            externalIDResolver: StubExternalIDResolver(value: "tt1234567"),
            session: URLSession(configuration: .ephemeral)
        )
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await provider.findSources(
                for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, tmdbID: 42)
            )
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled provider request must throw cancellation.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }
    }

    func testManyConfiguredAddonsUseBoundedParallelRequests() async throws {
        BoundedAddonURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedAddonURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let urls = (0..<12).map { URL(string: "https://addons.example.test/instance-\($0)/manifest.json")! }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: urls,
            externalIDResolver: StubExternalIDResolver(value: "tt1234567"),
            session: session
        )
        let result = try await provider.discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .movie))
        let statistics = BoundedAddonURLProtocol.statistics()
        XCTAssertEqual(result.providerStatuses.count, 12)
        XCTAssertEqual(statistics.completed, 12)
        XCTAssertLessThanOrEqual(statistics.maximum, 4)
        XCTAssertGreaterThan(statistics.maximum, 1)
    }

    func testSeparateConfigurationsOnSameHostHaveIndependentCounts() async throws {
        ProviderStubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("manifest.json") {
                return (self.response(request, 200), Data(#"{"id":"addon","version":"1","name":"Addon","resources":["stream"],"types":["movie"]}"#.utf8))
            }
            let body = request.url!.path.contains("first")
                ? #"{"streams":[{"url":"https://media.example.test/movie.mp4"}]}"#
                : #"{"streams":[]}"#
            return (self.response(request, 200), Data(body.utf8))
        }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [URL(string: "https://addons.example.test/first/manifest.json")!, URL(string: "https://addons.example.test/second/manifest.json")!],
            externalIDResolver: StubExternalIDResolver(value: "tt1234567"), session: makeSession()
        )
        let result = try await provider.discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .movie))
        XCTAssertEqual(result.providerStatuses.map(\.outcome), [.found(directSourceCount: 1, torrentSourceCount: 0), .noSources])
    }

    override func tearDown() {
        ProviderStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testProviderResolvesIMDbIDAndReturnsOnlyDirectPlaybackURLs() async throws {
        ProviderStubURLProtocol.handler = { request in
            if request.url?.path == "/addon/manifest.json" {
                return (self.response(request, 200), Data(#"{"id":"test.addon","version":"1","name":"Test Add-on","resources":["stream"],"types":["movie"],"idPrefixes":["tt"]}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/addon/stream/movie/tt1234567.json")
            return (self.response(request, 200), Data(#"{"streams":[{"name":"1080p MP4","url":"https://media.example.test/movie.mp4"},{"name":"Torrent","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":0}]}"#.utf8))
        }
        let resolver = StubExternalIDResolver(value: "tt1234567")
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [URL(string: "https://addons.example.test/addon/manifest.json")!],
            externalIDResolver: resolver,
            session: makeSession()
        )

        let sources = try await provider.findSources(
            for: PlaybackSourceRequest(title: "Example", mediaKind: .movie, tmdbID: 42)
        )

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.title, "1080p MP4")
        XCTAssertEqual(sources.first?.qualityLabel, "1080P")
        XCTAssertTrue(sources.first?.supportsNativePlayback == true)
        XCTAssertEqual(sources.first?.url.absoluteString, "https://media.example.test/movie.mp4")
    }

    func testDiscoverReturnsDirectSourcesAndValidatedTorrentDescriptorsSeparately() async throws {
        ProviderStubURLProtocol.handler = { request in
            if request.url?.path == "/manifest.json" {
                return (self.response(request, 200), Data(#"{"id":"discovery.addon","version":"1","name":"Discovery","resources":["stream"],"types":["movie"],"idPrefixes":["tt"]}"#.utf8))
            }
            return (self.response(request, 200), Data(#"{"streams":[{"name":"Direct","url":"https://media.example.test/movie.mp4"},{"name":"Torrent","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":2},{"name":"Invalid torrent","infoHash":"not-a-hash","fileIdx":0}]}"#.utf8))
        }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [URL(string: "https://addons.example.test/manifest.json")!],
            externalIDResolver: StubExternalIDResolver(value: "tt1234567"),
            session: makeSession()
        )

        let discovery = try await provider.discover(
            for: PlaybackSourceRequest(title: "Example", mediaKind: .movie, tmdbID: 42)
        )

        XCTAssertEqual(discovery.sources.count, 1)
        XCTAssertEqual(discovery.sources.first?.url.absoluteString, "https://media.example.test/movie.mp4")
        XCTAssertEqual(discovery.torrentDescriptors.count, 1)
        XCTAssertEqual(discovery.torrentDescriptors.first?.infoHash, "0123456789abcdef0123456789abcdef01234567")
        XCTAssertEqual(discovery.torrentDescriptors.first?.fileIndex, 2)
    }

    func testSameTorrentFromDifferentAddonsKeepsBothProviderChoices() async throws {
        ProviderStubURLProtocol.handler = { request in
            if request.url?.path == "/manifest.json" {
                return (self.response(request, 200), Data(#"{"id":"addon","version":"1","name":"Addon","resources":["stream"],"types":["movie"],"idPrefixes":["tt"]}"#.utf8))
            }
            return (self.response(request, 200), Data(#"{"streams":[{"name":"1080p Torrent","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":0}]}"#.utf8))
        }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [
                URL(string: "https://torrentio.strem.fun/manifest.json")!,
                URL(string: "https://mediafusion.elfhosted.com/manifest.json")!
            ],
            externalIDResolver: StubExternalIDResolver(value: "tt1234567"),
            session: makeSession()
        )

        let discovery = try await provider.discover(
            for: PlaybackSourceRequest(title: "Example", mediaKind: .movie, imdbID: "tt1234567")
        )

        XCTAssertEqual(discovery.torrentDescriptors.count, 2)
        XCTAssertEqual(Set(discovery.torrentDescriptors.map(\.providerName)), Set(["Torrentio", "MediaFusion ElfHosted"]))
    }

    func testOneAddonFailureDoesNotHideTheOtherAddonsResults() async throws {
        ProviderStubURLProtocol.handler = { request in
            if request.url?.host == "mediafusion.elfhosted.com" {
                throw URLError(.timedOut)
            }
            if request.url?.path == "/manifest.json" {
                return (
                    self.response(request, 200),
                    Data(#"{"id":"torrentio","version":"1","name":"Torrentio","resources":["stream"],"types":["movie"],"idPrefixes":["tt"]}"#.utf8)
                )
            }
            return (
                self.response(request, 200),
                Data(#"{"streams":[{"name":"1080p Torrent","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":0}]}"#.utf8)
            )
        }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [
                URL(string: "https://torrentio.strem.fun/manifest.json")!,
                URL(string: "https://mediafusion.elfhosted.com/manifest.json")!
            ],
            externalIDResolver: StubExternalIDResolver(value: "tt1234567"),
            session: makeSession()
        )

        let discovery = try await provider.discover(
            for: PlaybackSourceRequest(title: "Example", mediaKind: .movie, imdbID: "tt1234567")
        )

        XCTAssertEqual(discovery.torrentDescriptors.count, 1)
        XCTAssertEqual(discovery.torrentDescriptors.first?.providerName, "Torrentio")
        XCTAssertEqual(discovery.providerStatuses.count, 2)
        XCTAssertTrue(discovery.providerStatuses.contains { status in
            guard status.name == "Torrentio" else { return false }
            if case .found(directSourceCount: _, torrentSourceCount: 1) = status.outcome {
                return true
            }
            return false
        })
        XCTAssertTrue(discovery.providerStatuses.contains { status in
            guard status.name == "MediaFusion ElfHosted" else { return false }
            if case .failed = status.outcome {
                return true
            }
            return false
        })
    }

    func testProviderUsesExactSeriesEpisodeCoordinates() async throws {
        ProviderStubURLProtocol.handler = { request in
            if request.url?.path == "/manifest.json" {
                return (self.response(request, 200), Data(#"{"id":"series.addon","version":"1","name":"Series Add-on","resources":["stream"],"types":["series"],"idPrefixes":["tt"]}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/stream/series/tt7654321:3:4.json")
            return (self.response(request, 200), Data(#"{"streams":[{"title":"Episode stream","url":"https://media.example.test/episode.m3u8"}]}"#.utf8))
        }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [URL(string: "https://addons.example.test/manifest.json")!],
            externalIDResolver: StubExternalIDResolver(value: "tt7654321"),
            session: makeSession()
        )

        let sources = try await provider.findSources(
            for: PlaybackSourceRequest(title: "Example Series", mediaKind: .series, tmdbID: 55, seasonNumber: 3, episodeNumber: 4)
        )

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.url.absoluteString, "https://media.example.test/episode.m3u8")
    }

    func testProviderReturnsEmptyWhenExternalIDIsUnavailable() async throws {
        ProviderStubURLProtocol.handler = { _ in
            XCTFail("No network call should happen without an IMDb ID.")
            throw URLError(.cancelled)
        }
        let provider = try StremioAddonPlaybackProvider(
            manifestURLs: [URL(string: "https://addons.example.test/manifest.json")!],
            externalIDResolver: StubExternalIDResolver(value: nil),
            session: makeSession()
        )

        let sources = try await provider.findSources(
            for: PlaybackSourceRequest(title: "Example", mediaKind: .movie, tmdbID: 42)
        )

        XCTAssertTrue(sources.isEmpty)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(_ request: URLRequest, _ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }
}

private struct StubExternalIDResolver: PlaybackExternalIDResolving {
    let value: String?

    func imdbID(for request: PlaybackSourceRequest) async throws -> String? {
        value
    }
}

private final class ProviderStubURLProtocol: URLProtocol {
    private static let handlerStorage = LockedURLRequestHandler()
    static var handler: LockedURLRequestHandler.Handler? {
        get { handlerStorage.handler }
        set { handlerStorage.handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class BoundedAddonURLProtocol: URLProtocol {
    // URLProtocol explicitly cannot conform to Sendable. Only this one-shot response crosses
    // the task boundary; its lock arbitrates cancellation/delivery and owns the callback target.
    // Keep this test-only bridge until URLProtocol has a concurrency-safe callback API.
    private final class PendingResponse: @unchecked Sendable {
        private let lock = NSLock()
        private var target: BoundedAddonURLProtocol?
        private var cancelled = false
        func install(_ target: BoundedAddonURLProtocol) {
            lock.lock()
            defer { lock.unlock() }
            if !cancelled { self.target = target }
        }
        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            target = nil
        }
        func deliver() {
            lock.lock()
            let target = self.target
            self.target = nil
            lock.unlock()
            target?.finish(#"{"streams":[]}"#)
        }
    }
    private let pendingResponse = PendingResponse()
    private static let lock = NSLock()
    nonisolated(unsafe) private static var active = 0
    nonisolated(unsafe) private static var maximum = 0
    nonisolated(unsafe) private static var completed = 0

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        active = 0; maximum = 0; completed = 0
    }

    static func statistics() -> (maximum: Int, completed: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (maximum, completed)
    }

    private static func beganStream() {
        lock.lock()
        defer { lock.unlock() }
        active += 1
        maximum = max(maximum, active)
    }

    private static func endedStream() {
        lock.lock()
        defer { lock.unlock() }
        active -= 1
        completed += 1
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url!.path.hasSuffix("manifest.json") {
            finish(#"{"id":"bounded","version":"1","name":"Bounded","resources":["stream"],"types":["movie"]}"#)
        } else {
            Self.beganStream()
            let pending = pendingResponse
            pending.install(self)
            Task.detached {
                try? await Task.sleep(nanoseconds: 50_000_000)
                Self.endedStream()
                pending.deliver()
            }
        }
    }

    private func finish(_ json: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { pendingResponse.cancel() }
}
