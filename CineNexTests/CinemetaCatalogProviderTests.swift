import Foundation
import XCTest
@testable import CineNex

final class CinemetaCatalogProviderTests: XCTestCase {
    override func tearDown() {
        CinemetaStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testCatalogCombinesMoviesAndSeriesWithoutCredentials() async throws {
        CinemetaStubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "v3-cinemeta.strem.io")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let isMovie = request.url?.path.contains("/movie/") == true
            let body = isMovie
                ? #"{"metas":[{"imdb_id":"tt1234567","type":"movie","name":"Example Film","poster":"https://images.example.test/poster.jpg","description":"A story.","releaseInfo":"2024","genres":["Drama"],"imdbRating":"8.2"}]}"#
                : #"{"metas":[{"imdb_id":"tt7654321","type":"series","name":"Example Series","releaseInfo":"2022","genres":["Mystery"]}]}"#
            return (self.response(request, 200), Data(body.utf8))
        }

        let items = try await CinemetaCatalogProvider(session: makeSession()).fetchCatalog()

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains(where: { $0.title == "Example Film" && $0.kind == .movie }))
        XCTAssertTrue(items.contains(where: { $0.title == "Example Series" && $0.kind == .series }))
        XCTAssertEqual(items.first(where: { $0.title == "Example Film" })?.rating, 8.2)
        XCTAssertEqual(items.first(where: { $0.title == "Example Film" })?.posterURL?.absoluteString, "https://images.example.test/poster.jpg")
    }

    func testCatalogRequestsMultipleGenresAndDeduplicatesAcrossFeeds() async throws {
        let requestedPaths = CatalogRequestRecorder()
        CinemetaStubURLProtocol.handler = { request in
            requestedPaths.insert(request.url?.path ?? "")
            let isMovie = request.url?.path.contains("/movie/") == true
            let body = isMovie
                ? #"{\"metas\":[{\"id\":\"tt1234567\",\"type\":\"movie\",\"name\":\"Example Film\",\"releaseInfo\":\"2024\"}]}"#
                : #"{\"metas\":[{\"id\":\"tt7654321\",\"type\":\"series\",\"name\":\"Example Series\",\"releaseInfo\":\"2022\"}]}"#
            return (self.response(request, 200), Data(body.utf8))
        }
        let items = try await CinemetaCatalogProvider(session: makeSession()).fetchCatalog()
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(requestedPaths.values.contains("/catalog/movie/top.json"))
        XCTAssertTrue(requestedPaths.values.contains("/catalog/movie/top/genre=Action.json"))
        XCTAssertTrue(requestedPaths.values.contains("/catalog/series/top/genre=Drama.json"))
    }

    func testSearchEncodesQueryAndRejectsInvalidImageURLs() async throws {
        CinemetaStubURLProtocol.handler = { request in
            let encodedPath = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath
            XCTAssertTrue(encodedPath?.contains("/search=A%20%26%20B.json") == true)
            let body = #"{"metas":[{"id":"tt1234567","type":"movie","name":"Example Film","poster":"http://images.example.test/poster.jpg","releaseInfo":"2024"}]}"#
            return (self.response(request, 200), Data(body.utf8))
        }

        let items = try await CinemetaCatalogProvider(session: makeSession()).search(query: "A & B")

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.posterURL)
        XCTAssertEqual(items.first?.metadataProvider, "cinemeta")
        XCTAssertNil(items.first?.externalID)
    }

    func testSearchWithBlankQueryDoesNotMakeRequests() async throws {
        CinemetaStubURLProtocol.handler = { _ in
            XCTFail("A blank query must not trigger network traffic.")
            throw URLError(.cancelled)
        }

        let items = try await CinemetaCatalogProvider(session: makeSession()).search(query: "  \n ")

        XCTAssertTrue(items.isEmpty)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CinemetaStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(_ request: URLRequest, _ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }
}

private final class CatalogRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<String>()
    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
    func insert(_ path: String) {
        lock.lock()
        paths.insert(path)
        lock.unlock()
    }
}

private final class CinemetaStubURLProtocol: URLProtocol {
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
