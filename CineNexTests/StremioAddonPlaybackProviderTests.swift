import Foundation
import XCTest
@testable import CineNex

final class StremioAddonPlaybackProviderTests: XCTestCase {
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
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

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
