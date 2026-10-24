import Foundation
import XCTest
@testable import CineNex

final class StremioAddonClientTests: XCTestCase {
    func testCancelledManifestRequestPropagatesCancellation() async {
        StremioStubURLProtocol.handler = { request in
            XCTFail("A cancelled manifest request must not issue a network request.")
            return (
                self.response(for: request, statusCode: 200),
                Data(#"{"id":"test.addon","version":"1.0.0","name":"Test Add-on","resources":["stream"],"types":["movie"]}"#.utf8)
            )
        }
        defer { StremioStubURLProtocol.handler = nil }

        let client = try! StremioAddonClient(
            manifestURL: URL(string: "https://addons.example.test/manifest.json")!,
            session: makeSession()
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
            XCTAssertEqual(requestCount, 0)
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }
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
