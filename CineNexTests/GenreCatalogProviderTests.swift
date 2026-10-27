import XCTest
@testable import CineNex

final class GenreCatalogProviderTests: XCTestCase {
    override func tearDown() {
        GenreCatalogURLProtocol.requests.handler = nil
        super.tearDown()
    }
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenreCatalogURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func response(_ request: URLRequest, _ payload: String) throws -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data(payload.utf8))
    }
    private func item(_ id: String, kind: MediaKind = .movie, genre: String = "Action") -> MediaItem {
        MediaItem(id: id, title: id, kind: kind, year: 2024, genre: genre, synopsis: "", symbol: "film", runtime: "", streamURL: nil)
    }

    func testGenreAliasesRespectMovieAndTVTaxonomiesAndNeverMatchSubstrings() {
        XCTAssertEqual(GenreCatalogGenres.tmdbIDs("Action", kind: .movie), [28])
        XCTAssertEqual(GenreCatalogGenres.tmdbIDs("Adventure", kind: .series), [10759])
        XCTAssertEqual(GenreCatalogGenres.tmdbIDs("Science Fiction", kind: .series), [10765])
        XCTAssertTrue(GenreCatalogQuery(genre: "Action", kind: .series).matches(item("tv", kind: .series, genre: "Action & Adventure · Drama")))
        XCTAssertFalse(GenreCatalogQuery(genre: "Drama").matches(item("wrong", genre: "Dramedy")))
        XCTAssertFalse(GenreCatalogQuery(genre: "Action", kind: .movie).matches(item("tv", kind: .series)))
    }

    func testTMDBRequestsGenreAndTypePagesAndKeepsIndependentTypeCursors() async throws {
        GenreCatalogURLProtocol.requests.handler = { request in
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = query.first { $0.name == "page" }?.value
            let isMovie = url.path.hasSuffix("/movie")
            XCTAssertEqual(url.host, "api.themoviedb.org")
            XCTAssertEqual(query.first { $0.name == "with_genres" }?.value, isMovie ? "28" : "10759")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            if isMovie { XCTAssertEqual(page, "1") }
            let total = isMovie ? 1 : 2
            let id = isMovie ? 101 : (page == "1" ? 201 : 202)
            let kindName = isMovie ? "title" : "name"
            let genres = isMovie ? "28" : "10759"
            return try self.response(request, "{\"page\":\(page ?? "1"),\"total_pages\":\(total),\"results\":[{\"id\":\(id),\"\(kindName)\":\"Title\",\"genre_ids\":[\(genres)]}]}")
        }
        let provider = GenreCatalogProvider(readAccessToken: "fixture", session: makeSession())
        let query = GenreCatalogQuery(genre: "Action")
        let first = try await provider.page(query: query, cursor: nil)
        XCTAssertEqual(first.items.count, 2)
        XCTAssertEqual(first.next?.positions, ["tmdb-Series": 2])
        let second = try await provider.page(query: query, cursor: first.next)
        XCTAssertEqual(second.items.map(\.id), ["tmdb-tv-202"])
        XCTAssertNil(second.next)
    }

    func testUnknownGenreDoesNotFallBackToAllCatalogNetworkRequests() async throws {
        GenreCatalogURLProtocol.requests.handler = { _ in XCTFail("Unknown genre must not fetch all trending"); throw URLError(.badURL) }
        do {
            _ = try await GenreCatalogProvider(readAccessToken: "fixture", session: makeSession()).page(query: GenreCatalogQuery(genre: "Invented Category"), cursor: nil)
            XCTFail("Expected unsupported genre")
        } catch let error as GenreCatalogError { XCTAssertEqual(error, .unsupportedGenre("Invented Category")) }
    }

    func testCinemetaUsesCombinedGenreSkipPathAndRawCountForPagination() async throws {
        GenreCatalogURLProtocol.requests.handler = { request in
            XCTAssertEqual(request.url?.path, "/catalog/movie/top/genre=Sci-Fi&skip=100.json")
            let metas: [[String: Any]] = (0..<100).map { index in
                ["id": String(format: "tt%07d", index + 1), "type": "movie", "name": index == 0 ? "Valid movie" : "", "genres": ["Sci-Fi"]]
            }
            let data = try JSONSerialization.data(withJSONObject: ["metas": metas])
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let page = try await CinemetaCatalogProvider(session: makeSession()).catalogPage(type: "movie", genre: "Sci-Fi", skip: 100)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.rawCount, 100)
        XCTAssertTrue(page.hasMore)
    }

    @MainActor
    func testSparseDuplicatePagesRefillAutomaticallyAndDeduplicateAgainstSeeds() async {
        let seeded = item("seed")
        let extra = item("new")
        let provider = GenreCatalogFixture(pages: [
            GenreCatalogPage(items: [seeded], next: GenreCatalogCursor(positions: ["p": 2])),
            GenreCatalogPage(items: [], next: GenreCatalogCursor(positions: ["p": 3])),
            GenreCatalogPage(items: [extra, extra], next: nil)])
        let model = GenreCatalogModel(query: GenreCatalogQuery(genre: "Action"), seedItems: [seeded], provider: provider)
        await model.reload()
        XCTAssertEqual(model.items.map(\.id), ["seed", "new"])
        XCTAssertEqual(model.pagesLoaded, 3)
        XCTAssertFalse(model.hasMore)
    }

    @MainActor
    func testEmptyVisibleRefillIsBoundedInsteadOfScanningForever() async {
        let provider = GenreCatalogFixture(pages: (0..<10).map { index in
            GenreCatalogPage(items: [], next: GenreCatalogCursor(positions: ["p": index + 2]))
        })
        let model = GenreCatalogModel(query: GenreCatalogQuery(), seedItems: [], provider: provider)
        await model.reload()
        XCTAssertEqual(model.pagesLoaded, 3)
        XCTAssertTrue(model.autoFillPaused)
        XCTAssertTrue(model.hasMore)
    }
}

private actor GenreCatalogFixture: GenreCatalogPaging {
    private var pages: [GenreCatalogPage]
    init(pages: [GenreCatalogPage]) { self.pages = pages }
    func page(query: GenreCatalogQuery, cursor: GenreCatalogCursor?) async throws -> GenreCatalogPage {
        guard !pages.isEmpty else { throw GenreCatalogError.invalidPage }
        return pages.removeFirst()
    }
}

private final class GenreCatalogURLProtocol: URLProtocol {
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
