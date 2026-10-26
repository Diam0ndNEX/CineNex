import Foundation
import XCTest
@testable import CineNex

final class SceneBoxTorrentSearchTests: XCTestCase {
    override func tearDown() {
        SceneBoxSearchURLProtocol.state.set(nil)
        super.tearDown()
    }

    func testMovieURLAndDistinctDirectSourceIdentities() async {
        SceneBoxSearchURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.absoluteString, "https://addons.example.test/config/stream/movie/tt1234567.json")
            return (200, #"{"streams":[{"name":"First","url":"https://media.example.test/first.mp4"},{"name":"Second","url":"https://media.example.test/second.mp4"}]}"#)
        }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let result = await SceneBoxTorrentSearch(sourceBases: ["https://addons.example.test/config"], session: session)
            .discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .movie), externalIDResolver: SearchIMDbResolver())
        XCTAssertEqual(result.sources.count, 2)
        XCTAssertEqual(Set(result.sources.map(\.id)).count, 2)
        XCTAssertTrue(result.sources.allSatisfy { $0.id.contains("tt1234567") })
    }

    func testSeriesURLIncludesSeasonAndEpisode() async {
        SceneBoxSearchURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.absoluteString, "https://addons.example.test/stream/series/tt1234567:2:3.json")
            return (200, #"{"streams":[{"infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":2}]}"#)
        }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let result = await SceneBoxTorrentSearch(sourceBases: ["https://addons.example.test"], session: session)
            .discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .series, seasonNumber: 2, episodeNumber: 3), externalIDResolver: SearchIMDbResolver())
        XCTAssertEqual(result.torrentDescriptors.count, 1)
        XCTAssertEqual(result.torrentDescriptors.first?.fileIndex, 2)
    }

    func testFallsBackAfterConfiguredEndpointFails() async {
        SceneBoxSearchURLProtocol.state.set { request in
            if request.url?.path.hasPrefix("/config/") == true { return (503, "") }
            XCTAssertEqual(request.url?.path, "/stream/movie/tt1234567.json")
            return (200, #"{"streams":[{"url":"https://media.example.test/fallback.mp4"}]}"#)
        }
        let result = await discoverWithFallback()
        XCTAssertEqual(result.sources.first?.url.absoluteString, "https://media.example.test/fallback.mp4")
    }

    func testFallsBackWhenConfiguredEndpointContainsNoUsableEntries() async {
        SceneBoxSearchURLProtocol.state.set { request in
            if request.url?.path.hasPrefix("/config/") == true {
                return (200, #"{"streams":[{"infoHash":"invalid"},{"url":"javascript:alert(1)"}]}"#)
            }
            return (200, #"{"streams":[{"url":"https://media.example.test/fallback.mp4"}]}"#)
        }
        let result = await discoverWithFallback()
        XCTAssertEqual(result.sources.first?.url.absoluteString, "https://media.example.test/fallback.mp4")
    }

    private func discoverWithFallback() async -> StremioAddonDiscovery {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        return await SceneBoxTorrentSearch(
            sourceBases: ["https://addons.example.test/config", "https://addons.example.test"], session: session
        ).discover(for: PlaybackSourceRequest(title: "Example", mediaKind: .movie), externalIDResolver: SearchIMDbResolver())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SceneBoxSearchURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct SearchIMDbResolver: PlaybackExternalIDResolving {
    func imdbID(for request: PlaybackSourceRequest) async throws -> String? { "tt1234567" }
}

private final class SceneBoxSearchURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, String)

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func set(_ handler: Handler?) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
        }

        func get() -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
    }

    static let state = State()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.state.get(), let url = request.url else { throw URLError(.badServerResponse) }
            let (status, payload) = try handler(request)
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(payload.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
