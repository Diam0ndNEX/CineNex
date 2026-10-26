import Foundation
import XCTest
@testable import CineNex

final class StremioAddonClientTests: XCTestCase {
    func testCancelledManifestRequestPropagatesCancellation() async {
        StremioCancellationURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StremioCancellationURLProtocol.self]
        let client = try! StremioAddonClient(
            manifestURL: URL(string: "https://addons.example.test/manifest.json")!,
            session: URLSession(configuration: configuration)
        )

        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await client.fetchManifest()
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled manifest request must throw cancellation.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }

        XCTAssertEqual(StremioCancellationURLProtocol.requestCount, 0)
    }

    override func tearDown() {
        StremioStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchStreamsBuildsStandardMovieEndpointAndKeepsDirectAndTorrentEntries() async throws {
        StremioStubURLProtocol.handler = { request in
            if request.url?.path == "/addon/manifest.json" {
                return (self.response(for: request, statusCode: 200), Data(#"{"id":"test.addon","version":"1.0.0","name":"Test Add-on","resources":["stream"],"types":["movie","series"],"idPrefixes":["tt"]}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/addon/stream/movie/tt1234567.json")
            return (self.response(for: request, statusCode: 200), Data(#"{"streams":[{"name":"Direct HD","url":"https://media.example.test/movie.m3u8"},{"name":"Torrent HD","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":2},{"name":"Unsafe","url":"javascript:alert(1)"}]}"#.utf8))
        }
        let client = try StremioAddonClient(manifestURL: URL(string: "https://addons.example.test/addon/manifest.json")!, session: makeSession())

        let streams = try await client.fetchStreams(for: StremioStreamRequest(mediaType: "movie", itemID: "tt1234567"))

        XCTAssertEqual(streams.count, 3)
        XCTAssertEqual(streams[0].validatedPlaybackURL?.absoluteString, "https://media.example.test/movie.m3u8")
        XCTAssertEqual(streams[1].infoHash, "0123456789abcdef0123456789abcdef01234567")
        XCTAssertEqual(streams[1].fileIndex, 2)
        XCTAssertNil(streams[2].validatedPlaybackURL)
    }

    func testSeriesEndpointIncludesSeasonAndEpisodeInProtocolID() async throws {
        StremioStubURLProtocol.handler = { request in
            if request.url?.path == "/manifest.json" {
                return (self.response(for: request, statusCode: 200), Data(#"{"id":"series.addon","version":"1","name":"Series","resources":[{"name":"stream","types":["series"],"idPrefixes":["tt"]}],"types":["series"]}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/stream/series/tt7654321:2:9.json")
            return (self.response(for: request, statusCode: 200), Data(#"{"streams":[]}"#.utf8))
        }
        let client = try StremioAddonClient(manifestURL: URL(string: "https://addons.example.test/manifest.json")!, session: makeSession())

        let streams = try await client.fetchStreams(
            for: StremioStreamRequest(mediaType: "series", itemID: "tt7654321", seasonNumber: 2, episodeNumber: 9)
        )

        XCTAssertTrue(streams.isEmpty)
    }

    func testRejectsManifestURLsThatAreNotSafeHTTPS() {
        XCTAssertThrowsError(try StremioAddonClient(manifestURL: URL(string: "http://addons.example.test/manifest.json")!)) { error in
            XCTAssertEqual(error as? StremioAddonClientError, .invalidManifestURL)
        }
        XCTAssertThrowsError(try StremioAddonClient(manifestURL: URL(string: "https://user:pass@addons.example.test/manifest.json")!)) { error in
            XCTAssertEqual(error as? StremioAddonClientError, .invalidManifestURL)
        }
    }

    func testSeriesProtocolIDTracksSelectedSeasonAndEpisode() {
        let firstEpisode = StremioStreamRequest(
            mediaType: "series",
            itemID: "tt1234567",
            seasonNumber: 1,
            episodeNumber: 1
        )
        let laterEpisode = StremioStreamRequest(
            mediaType: "series",
            itemID: "tt1234567",
            seasonNumber: 3,
            episodeNumber: 7
        )

        XCTAssertEqual(firstEpisode.protocolID, "tt1234567:1:1")
        XCTAssertEqual(laterEpisode.protocolID, "tt1234567:3:7")
        XCTAssertNotEqual(firstEpisode.protocolID, laterEpisode.protocolID)
    }

    func testMovieProtocolIDDoesNotAddEpisodeSuffix() {
        let movie = StremioStreamRequest(mediaType: "movie", itemID: "tt1234567")

        XCTAssertEqual(movie.protocolID, "tt1234567")
    }

    func testRejectsMalformedStreamRequestBeforeNetworking() async throws {
        StremioStubURLProtocol.handler = { _ in
            XCTFail("Invalid requests must not perform network calls.")
            throw URLError(.cancelled)
        }
        let client = try StremioAddonClient(manifestURL: URL(string: "https://addons.example.test/manifest.json")!, session: makeSession())

        do {
            _ = try await client.fetchStreams(for: StremioStreamRequest(mediaType: "series", itemID: "tt1234567", seasonNumber: 1))
            XCTFail("Expected invalidRequest.")
        } catch {
            XCTAssertEqual(error as? StremioAddonClientError, .invalidRequest)
        }
    }

    func testHTTPSValidationRejectsDowngradedAndCredentialedURLs() {
        XCTAssertFalse(StremioAddonClient.isSafeHTTPSURL(URL(string: "http://addons.example.test/manifest.json")!))
        XCTAssertFalse(StremioAddonClient.isSafeHTTPSURL(URL(string: "https://user:pass@addons.example.test/manifest.json")!))
        XCTAssertTrue(StremioAddonClient.isSafeHTTPSURL(URL(string: "https://addons.example.test/manifest.json")!))
    }

    func testRedirectDelegateRejectsDowngradedAndCredentialedRedirects() {
        let delegate = StremioHTTPSRedirectDelegate()
        let originalURL = URL(string: "https://addons.example.test/manifest.json")!
        let response = HTTPURLResponse(
            url: originalURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "http://unsafe.example.test/manifest.json"]
        )!
        let task = URLSession.shared.dataTask(with: originalURL)

        for target in [
            URL(string: "http://unsafe.example.test/manifest.json")!,
            URL(string: "https://user:pass@addons.example.test/manifest.json")!
        ] {
            var followedURL: URL?
            delegate.urlSession(
                URLSession.shared,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: target)
            ) { request in
                followedURL = request?.url
            }
            XCTAssertNil(followedURL)
        }

        let allowedURL = URL(string: "https://cdn.example.test/manifest.json")!
        var followedURL: URL?
        delegate.urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: allowedURL)
        ) { request in
            followedURL = request?.url
        }
        XCTAssertEqual(followedURL, allowedURL)
    }

    func testMalformedStreamEntriesDoNotDiscardValidMediaFusionResults() throws {
        let payload = """
        {
          "streams": [
            17,
            {"name":"Torrentio","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":0,"sources":["tracker:udp://tracker.example:80"]},
            {"name":"broken URL field","url":17,"infoHash":null},
            {"name":"MediaFusion direct","url":"https://media.example/video.mkv","title":"1080p WEB-DL"}
          ]
        }
        """
        let response = try JSONDecoder().decode(StremioStreamResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.streams.count, 3)
        XCTAssertEqual(response.streams[0].infoHash, "0123456789abcdef0123456789abcdef01234567")
        XCTAssertNil(response.streams[1].url)
        XCTAssertEqual(response.streams[2].url?.absoluteString, "https://media.example/video.mkv")
    }

    func testReportsHTTPFailureInsteadOfTreatingItAsAnEmptyResult() async throws {
        StremioStubURLProtocol.handler = { request in
            (self.response(for: request, statusCode: 503), Data())
        }
        let client = try StremioAddonClient(manifestURL: URL(string: "https://addons.example.test/manifest.json")!, session: makeSession())

        do {
            _ = try await client.fetchManifest()
            XCTFail("Expected HTTP error.")
        } catch {
            XCTAssertEqual(error as? StremioAddonClientError, .httpStatus(503))
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StremioStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }
}

private final class StremioStubURLProtocol: URLProtocol {
    private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var storedHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return storedHandler
        }
        set {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            storedHandler = newValue
        }
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

private final class StremioCancellationURLProtocol: URLProtocol {
    private static let requestCountLock = NSLock()
    nonisolated(unsafe) private static var storedRequestCount = 0

    static var requestCount: Int {
        get {
            requestCountLock.lock()
            defer { requestCountLock.unlock() }
            return storedRequestCount
        }
        set {
            requestCountLock.lock()
            defer { requestCountLock.unlock() }
            storedRequestCount = newValue
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
