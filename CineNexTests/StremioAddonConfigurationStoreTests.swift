import XCTest
@testable import CineNex

final class StremioAddonConfigurationStoreTests: XCTestCase {
    func testKeychainStoreRoundTripsValueAndOverwritesPreviousValue() throws {
        let store = KeychainStringStore(
            service: "com.diam0ndnex.cinenex.tests.stremio",
            account: UUID().uuidString
        )
        defer { try? store.delete() }

        XCTAssertNil(try store.load())
        try store.save("https://addons.example.test/custom/manifest.json")
        XCTAssertEqual(try store.load(), "https://addons.example.test/custom/manifest.json")

        try store.save("https://addons.example.test/updated/manifest.json")
        XCTAssertEqual(try store.load(), "https://addons.example.test/updated/manifest.json")
    }

    func testKeychainStoreCanPersistAnEmptyValue() throws {
        let store = KeychainStringStore(
            service: "com.diam0ndnex.cinenex.tests.stremio",
            account: UUID().uuidString
        )
        defer { try? store.delete() }

        try store.save("")
        XCTAssertEqual(try store.load(), "")
    }

    func testKeychainStoreDeleteIsIdempotent() throws {
        let store = KeychainStringStore(
            service: "com.diam0ndnex.cinenex.tests.stremio",
            account: UUID().uuidString
        )

        XCTAssertNoThrow(try store.delete())
        try store.save("https://addons.example.test/manifest.json")
        XCTAssertNoThrow(try store.delete())
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.delete())
    }
}
