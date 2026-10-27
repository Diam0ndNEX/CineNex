import XCTest
@testable import CineNex

final class SettingsCategorySearchTests: XCTestCase {
    func testProviderNamesFindTheConfigurationDestination() {
        XCTAssertEqual(CineNexSettingsCategory.matching("mediafusion"), [.providers])
        XCTAssertEqual(CineNexSettingsCategory.matching("ANILIST"), [.accounts])
        XCTAssertEqual(CineNexSettingsCategory.matching("subtitles"), [.playback])
    }

    func testSearchMatchesAllWordsAcrossCategoryTitleAndDescription() {
        XCTAssertEqual(CineNexSettingsCategory.matching("storage offline"), [.storage])
        XCTAssertEqual(CineNexSettingsCategory.matching(" \n "), CineNexSettingsCategory.allCases)
        XCTAssertTrue(CineNexSettingsCategory.matching("unsupported watch party").isEmpty)
    }

    func testDetailGenresAreUniqueActionableNamesRatherThanSeparators() {
        XCTAssertEqual(CatalogGenreTokens.values(from: "Horror • Thriller · Science Fiction, Horror | thriller"),
                       ["Horror", "Thriller", "Science Fiction"])
        XCTAssertEqual(CatalogGenreTokens.values(from: " , • · | "), [])
    }
}
