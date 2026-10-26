import Foundation
import XCTest
@testable import CineNex

final class TMDBCatalogProviderNetworkTests: XCTestCase {
    override func tearDown() {
        StubTMDBURLProtocol.handler = nil
        super.tearDown()
    }

    func testMissingTokenFailsBeforeMakingRequest() async {
        StubTMDBURLProtocol.handler = { _ in
            XCTFail("A request should not be made without a token.")
            throw URLError(.cancelled)
        }
        let provider = TMDBCatalogProvider(readAccessToken: "", session: makeSession())

        do {
            _ = try await provider.fetchCatalog()
            XCTFail("Expected missingToken.")
        } catch {
            guard case TMDBCatalogError.missingToken = error else {
                XCTFail("Expected missingToken, got \(error)")
                return
            }
        }
    }

    func testUnauthorizedResponseMapsToUnauthorizedError() async {
        StubTMDBURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (self.response(for: request, statusCode: 401), Data())
        }
        let provider = TMDBCatalogProvider(readAccessToken: "test-token", session: makeSession())

        do {
            _ = try await provider.fetchCatalog()
            XCTFail("Expected unauthorized.")
        } catch {
            guard case TMDBCatalogError.unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        }
    }

    func testRateLimitedResponseMapsToRateLimitedError() async {
        StubTMDBURLProtocol.handler = { request in
            (self.response(for: request, statusCode: 429), Data())
        }
        let provider = TMDBCatalogProvider(readAccessToken: "test-token", session: makeSession())

        do {
            _ = try await provider.fetchCatalog()
            XCTFail("Expected rateLimited.")
        } catch {
            guard case TMDBCatalogError.rateLimited = error else {
                XCTFail("Expected rateLimited, got \(error)")
                return
            }
        }
    }

    func testServerFailurePreservesHTTPStatusCode() async {
        StubTMDBURLProtocol.handler = { request in
            (self.response(for: request, statusCode: 503), Data())
        }
        let provider = TMDBCatalogProvider(readAccessToken: "test-token", session: makeSession())

        do {
            _ = try await provider.fetchCatalog()
            XCTFail("Expected server error.")
        } catch {
            guard case TMDBCatalogError.server(let statusCode) = error else {
                XCTFail("Expected server error, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 503)
        }
    }

    func testTransportFailureMapsToNetworkError() async {
        StubTMDBURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let provider = TMDBCatalogProvider(readAccessToken: "test-token", session: makeSession())

        do {
            _ = try await provider.fetchCatalog()
            XCTFail("Expected network error.")
        } catch {
            guard case TMDBCatalogError.network = error else {
                XCTFail("Expected network error, got \(error)")
                return
            }
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTMDBURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private final class StubTMDBURLProtocol: URLProtocol {
    private static let handlerStorage = LockedURLRequestHandler()
    static var handler: LockedURLRequestHandler.Handler? {
        get { handlerStorage.handler }
        set { handlerStorage.handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
