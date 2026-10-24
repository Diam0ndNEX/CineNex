import XCTest
@testable import CineNex

final class PlaybackProviderHealthStoreTests: XCTestCase {
    func testUnknownProviderCanBeQueried() async {
        let store = makeStore()
        let validProviderEligible = await store.shouldQuery(providerID: "provider-a")
        let blankProviderEligible = await store.shouldQuery(providerID: "   ")
        XCTAssertTrue(validProviderEligible)
        XCTAssertFalse(blankProviderEligible)
    }

    func testFailureAppliesExponentialCooldownAndCapsIt() async throws {
        let store = makeStore(baseCooldown: 10, maximumCooldown: 25)
        let start = Date(timeIntervalSince1970: 1_760_000_000)

        await store.recordFailure(providerID: "provider-a", message: "Timeout", at: start)
        let firstValue = await store.health(for: "provider-a")
        let first = try XCTUnwrap(firstValue)
        XCTAssertEqual(first.consecutiveFailures, 1)
        XCTAssertEqual(first.nextRetryAt, start.addingTimeInterval(10))
        XCTAssertEqual(first.lastErrorMessage, "Timeout")
        let beforeFirstRetry = await store.shouldQuery(providerID: "provider-a", at: start.addingTimeInterval(9))
        let atFirstRetry = await store.shouldQuery(providerID: "provider-a", at: start.addingTimeInterval(10))
        XCTAssertFalse(beforeFirstRetry)
        XCTAssertTrue(atFirstRetry)

        await store.recordFailure(providerID: "provider-a", message: "Still offline", at: start.addingTimeInterval(11))
        let secondValue = await store.health(for: "provider-a")
        let second = try XCTUnwrap(secondValue)
        XCTAssertEqual(second.consecutiveFailures, 2)
        XCTAssertEqual(second.nextRetryAt, start.addingTimeInterval(31))

        await store.recordFailure(providerID: "provider-a", message: "Third failure", at: start.addingTimeInterval(32))
        let thirdValue = await store.health(for: "provider-a")
        let third = try XCTUnwrap(thirdValue)
        XCTAssertEqual(third.consecutiveFailures, 3)
        XCTAssertEqual(third.nextRetryAt, start.addingTimeInterval(57))
    }

    func testSuccessClearsCooldownAndFailureMessage() async throws {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        await store.recordFailure(providerID: "provider-a", message: "Network error", at: date)
        await store.recordSuccess(providerID: "provider-a", at: date.addingTimeInterval(1))

        let value = await store.health(for: "provider-a")
        let record = try XCTUnwrap(value)
        XCTAssertEqual(record.consecutiveFailures, 0)
        XCTAssertNil(record.nextRetryAt)
        XCTAssertNil(record.lastErrorMessage)
        XCTAssertEqual(record.lastSuccessAt, date.addingTimeInterval(1))
        let eligibleAfterSuccess = await store.shouldQuery(providerID: "provider-a", at: date.addingTimeInterval(1))
        XCTAssertTrue(eligibleAfterSuccess)
    }

    func testRecordsPersistAcrossStoreInstances() async throws {
        let suiteName = "CineNexTests.PlaybackProviderHealth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_760_000_000)

        let firstStore = PlaybackProviderHealthStore(
            defaults: defaults,
            storageKey: "health",
            baseCooldown: 15,
            maximumCooldown: 60
        )
        await firstStore.recordFailure(providerID: "provider-b", message: "HTTP 503", at: date)

        let secondStore = PlaybackProviderHealthStore(
            defaults: defaults,
            storageKey: "health",
            baseCooldown: 15,
            maximumCooldown: 60
        )
        let value = await secondStore.health(for: "provider-b")
        let record = try XCTUnwrap(value)

        XCTAssertEqual(record.consecutiveFailures, 1)
        XCTAssertEqual(record.lastErrorMessage, "HTTP 503")
        let beforeRetry = await secondStore.shouldQuery(providerID: "provider-b", at: date.addingTimeInterval(14))
        let atRetry = await secondStore.shouldQuery(providerID: "provider-b", at: date.addingTimeInterval(15))
        XCTAssertFalse(beforeRetry)
        XCTAssertTrue(atRetry)
    }

    func testErrorMessageIsTrimmedAndBounded() async throws {
        let store = makeStore()
        await store.recordFailure(providerID: "provider-a", message: "  " + String(repeating: "x", count: 500) + "  ")
        let value = await store.health(for: "provider-a")
        let record = try XCTUnwrap(value)
        XCTAssertEqual(record.lastErrorMessage?.count, 300)
    }

    private func makeStore(
        baseCooldown: TimeInterval = 10,
        maximumCooldown: TimeInterval = 60
    ) -> PlaybackProviderHealthStore {
        let suiteName = "CineNexTests.PlaybackProviderHealth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PlaybackProviderHealthStore(
            defaults: defaults,
            storageKey: "health",
            baseCooldown: baseCooldown,
            maximumCooldown: maximumCooldown
        )
    }
}
