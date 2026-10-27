import XCTest
@testable import CineNex

final class SourceProviderPinsTests: XCTestCase {
    func testPinsPersistAndToggleWithoutLosingOtherProviders() {
        let first = SourceProviderPins.toggled("MediaFusion Midnight", in: "[]")
        let next = SourceProviderPins.toggled("Torrentio", in: first)
        XCTAssertEqual(SourceProviderPins.decode(next), ["MediaFusion Midnight", "Torrentio"])
        XCTAssertEqual(SourceProviderPins.decode(SourceProviderPins.toggled("MediaFusion Midnight", in: next)), ["Torrentio"])
    }

    func testOnlyAvailablePinsComeFirstAndOtherProvidersRemainVisible() {
        XCTAssertEqual(SourceProviderPins.ordered(["Torrentio", "MediaFusion", "Other", "Other"],
                       pinned: ["Offline provider", "MediaFusion"]), ["MediaFusion", "Other", "Torrentio"])
    }

    func testMalformedAndDuplicatePreferencesRecoverSafely() {
        XCTAssertEqual(SourceProviderPins.decode("broken"), [])
        XCTAssertEqual(SourceProviderPins.decode(#"[" MediaFusion ","MediaFusion","","Torrentio"]"#), ["MediaFusion", "Torrentio"])
        let recovered = SourceProviderPins.toggled("Torrentio", in: "broken")
        XCTAssertEqual(SourceProviderPins.decode(recovered), ["Torrentio"])
    }
}
