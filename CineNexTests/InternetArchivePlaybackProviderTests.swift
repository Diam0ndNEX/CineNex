import XCTest
@testable import CineNex

final class InternetArchivePlaybackProviderTests: XCTestCase {
    func testCancelledTaskDoesNotStartArchiveSearch() async {
        var requestCount = 0
        MockArchiveURLProtocol.responseHandler = { _ in
            requestCount += 1
            return (200, Data(#"{"response":{"docs":[]}}"#.utf8))
        }
        defer { MockArchiveURLProtocol.responseHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockArchiveURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let provider = InternetArchivePlaybackProvider(session: session)
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await provider.findSources(
                for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie)
            )
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled provider request must throw cancellation.")
        } catch is CancellationError {
            XCTAssertEqual(requestCount, 0)
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }
    }

    func testAcceptsOnlyPublicDomainLicenseLabels() {
        XCTAssertTrue(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/publicdomain/zero/1.0/"))
        XCTAssertTrue(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/publicdomain/mark/1.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/publicdomain/zero/not-a-license/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://user@creativecommons.org/publicdomain/zero/1.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/licenses/by/4.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/licenses/by-sa/4.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/licenses/by-nc/4.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/licenses/by-nd/4.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("http://creativecommons.org/licenses/by/4.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense("https://example.com/licenses/by/4.0/"))
        XCTAssertFalse(InternetArchivePlaybackProvider.isAllowedLicense(nil))
    }

    func testReturnsOnlyExactTitleLicensedPublicMP4Files() {
        let request = PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, releaseYear: 1932)
        let response: [String: Any] = [
            "metadata": [
                "title": "Example Film",
                "year": "1932",
                "licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/"
            ],
            "files": [
                ["name": "film.mp4", "format": "MPEG4"],
                ["name": "poster.jpg", "format": "JPEG"],
                ["name": "../outside.mp4", "format": "MPEG4"],
                ["name": "private.mp4", "format": "MPEG4", "private": "true"],
                ["name": "unlisted.mp4", "format": "Unknown"]
            ]
        ]

        let sources = InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: response,
            identifier: "example-film",
            request: request
        )

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.providerID, "internet-archive")
        XCTAssertEqual(sources.first?.providerName, "Internet Archive")
        XCTAssertEqual(sources.first?.url.absoluteString, "https://archive.org/download/example-film/film.mp4")
        XCTAssertTrue(sources.first?.supportsNativePlayback == true)
    }

    func testRejectsUnlicensedOrMismatchedRecords() {
        let request = PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, releaseYear: 1932)
        let unlicensed: [String: Any] = [
            "metadata": [
                "title": "Example Film",
                "year": "1932",
                "licenseurl": "https://example.com/license"
            ],
            "files": [["name": "film.mp4", "format": "MPEG4"]]
        ]
        let wrongTitle: [String: Any] = [
            "metadata": [
                "title": "Different Film",
                "year": "1932",
                "licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/"
            ],
            "files": [["name": "film.mp4", "format": "MPEG4"]]
        ]
        let wrongYear: [String: Any] = [
            "metadata": [
                "title": "Example Film",
                "year": "1940",
                "licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/"
            ],
            "files": [["name": "film.mp4", "format": "MPEG4"]]
        ]

        XCTAssertTrue(InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: unlicensed,
            identifier: "example-film",
            request: request
        ).isEmpty)
        XCTAssertTrue(InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: wrongTitle,
            identifier: "example-film",
            request: request
        ).isEmpty)
        XCTAssertTrue(InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: wrongYear,
            identifier: "example-film",
            request: request
        ).isEmpty)
    }


    func testFindSourcesAutomaticallySearchesAndResolvesAnEligibleFilm() async throws {
        MockArchiveURLProtocol.responseHandler = { request in
            switch request.url?.path {
            case "/advancedsearch.php":
                return (
                    200,
                    Data(#"{"response":{"docs":[{"identifier":"example-film","title":"Example Film","year":"1932"}]}}"#.utf8)
                )
            case "/metadata/example-film":
                return (
                    200,
                    Data(#"{"metadata":{"title":"Example Film","year":"1932","licenseurl":"https://creativecommons.org/publicdomain/zero/1.0/"},"files":[{"name":"film.mp4","format":"MPEG4"}]}"#.utf8)
                )
            default:
                return (404, Data(#"{"error":"not found"}"#.utf8))
            }
        }
        defer { MockArchiveURLProtocol.responseHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockArchiveURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let provider = InternetArchivePlaybackProvider(session: session)
        let result = try await provider.findSources(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, releaseYear: 1932)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.url.absoluteString, "https://archive.org/download/example-film/film.mp4")
        XCTAssertEqual(result.first?.providerID, "internet-archive")
    }

    func testRejectsUnsafeIdentifiersAndSeriesRequests() {
        let licensed: [String: Any] = [
            "metadata": [
                "title": "Example Film",
                "licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/"
            ],
            "files": [["name": "film.mp4", "format": "MPEG4"]]
        ]

        XCTAssertTrue(InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: licensed,
            identifier: "../other",
            request: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie)
        ).isEmpty)
        XCTAssertTrue(InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: licensed,
            identifier: "..",
            request: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie)
        ).isEmpty)
        XCTAssertTrue(InternetArchivePlaybackProvider.sources(
            fromMetadataResponse: licensed,
            identifier: "example-film",
            request: PlaybackSourceRequest(title: "Example Film", mediaKind: .series, seasonNumber: 1, episodeNumber: 1)
        ).isEmpty)
    }
}


private final class MockArchiveURLProtocol: URLProtocol {
    static var responseHandler: ((URLRequest) -> (statusCode: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "archive.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseHandler = Self.responseHandler,
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let result = responseHandler(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: result.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
