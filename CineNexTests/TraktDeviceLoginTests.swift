import Combine
import XCTest
@testable import CineNex

final class TraktDeviceLoginTests: XCTestCase {
    @MainActor
    func testPendingAuthorizationSurvivesObserverDetachRejectsDuplicateStartsAndExpires() async throws {
        let suite = "TraktDeviceLoginTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fixture-public-client", forKey: "cinenex.trakt.clientID")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceLoginURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let counts = DeviceLoginRequestCounts()
        defer { session.invalidateAndCancel(); DeviceLoginURLProtocol.requests.handler = nil }
        DeviceLoginURLProtocol.requests.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/oauth/device/code" {
                counts.recordCode()
                let data = Data(#"{"device_code":"fixture-device","user_code":"KEEP1234","verification_url":"https://auth.trakt.tv/activate","expires_in":3,"interval":1}"#.utf8)
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            XCTAssertEqual(url.path, "/oauth/device/token")
            counts.recordPoll()
            return (HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data())
        }
        let integration = TraktIntegration(defaults: defaults, session: session)
        defer { integration.cancelDeviceSignIn() }
        // A screen observes the app-owned session, then disappears for the browser handoff.
        let screenObservation = integration.objectWillChange.sink { _ in }
        integration.startDeviceSignIn()
        for _ in 0..<100 {
            if integration.activeAuthorization != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(integration.activeAuthorization?.userCode, "KEEP1234")
        screenObservation.cancel()
        integration.startDeviceSignIn()
        integration.startDeviceSignIn()
        // Polling must continue without a visible screen, with only one issued code.
        for _ in 0..<150 {
            if counts.polls > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(counts.codes, 1)
        XCTAssertGreaterThan(counts.polls, 0)
        XCTAssertEqual(integration.activeAuthorization?.userCode, "KEEP1234")
        // Retaining the task across navigation must not make it immortal.
        for _ in 0..<250 {
            if !integration.isAuthorizing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(integration.isAuthorizing)
        XCTAssertNil(integration.activeAuthorization)
        XCTAssertTrue(integration.lastError?.contains("expired") == true)
    }

    @MainActor
    func testDeviceLoginNeedsOnlyClientIDAndCancellationClearsPendingCode() async throws {
        let suite = "TraktDeviceLoginTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fixture-public-client", forKey: "cinenex.trakt.clientID")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceLoginURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); DeviceLoginURLProtocol.requests.handler = nil }
        DeviceLoginURLProtocol.requests.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://auth.trakt.tv/oauth/device/code")
            let data = Data(#"{"device_code":"fixture-device","user_code":"ABCD1234","verification_url":"https://auth.trakt.tv/activate","expires_in":600,"interval":20}"#.utf8)
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let integration = TraktIntegration(defaults: defaults, session: session)
        XCTAssertTrue(integration.loginAvailable)
        integration.startDeviceSignIn()
        for _ in 0..<100 {
            if integration.activeAuthorization != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(integration.activeAuthorization?.userCode, "ABCD1234")
        XCTAssertTrue(integration.isAuthorizing)
        integration.cancelDeviceSignIn()
        XCTAssertNil(integration.activeAuthorization)
        XCTAssertFalse(integration.isAuthorizing)
        // Let the old sleeping task resume its cancellation handler. It must not restore stale UI.
        await Task.yield()
        XCTAssertNil(integration.activeAuthorization)
        XCTAssertNil(integration.lastError)
        XCTAssertFalse(integration.isAuthorizing)
    }
}

private final class DeviceLoginURLProtocol: URLProtocol {
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

private final class DeviceLoginRequestCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var codeCount = 0
    private var pollCount = 0
    var codes: Int { lock.lock(); defer { lock.unlock() }; return codeCount }
    var polls: Int { lock.lock(); defer { lock.unlock() }; return pollCount }
    func recordCode() { lock.lock(); defer { lock.unlock() }; codeCount += 1 }
    func recordPoll() { lock.lock(); defer { lock.unlock() }; pollCount += 1 }
}
