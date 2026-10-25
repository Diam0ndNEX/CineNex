import XCTest
@testable import CineNex

final class AnimeWebsiteProviderTests: XCTestCase {
    func testEveryBundledProviderBuildsSecureSearchURL() throws {
        let anime = AnimeTitle(
            id: 21,
            title: "Your Name & Weathering with You",
            nativeTitle: "君の名は。",
            synopsis: "",
            episodeCount: 1,
            seasonYear: 2016,
            averageRating: 8.6,
            coverURL: nil,
            genres: [],
            format: "MOVIE",
            status: "FINISHED"
        )

        XCTAssertFalse(AnimeWebsiteProvider.supported.isEmpty)
        let providerIDs = Set(AnimeWebsiteProvider.supported.map(\.id))
        XCTAssertTrue(providerIDs.contains("miruro"))
        XCTAssertTrue(providerIDs.contains("anikoto"))
        XCTAssertTrue(providerIDs.contains("crunchyroll"))
        XCTAssertFalse(providerIDs.contains("animekai"))
        for provider in AnimeWebsiteProvider.supported {
            let url = provider.searchURL(for: anime)
            XCTAssertEqual(url?.scheme, "https")
            XCTAssertNotNil(url?.host)
            XCTAssertNil(url?.user)
            XCTAssertNil(url?.password)
            XCTAssertTrue(URLComponents(url: try XCTUnwrap(url), resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == provider.queryParameter && $0.value == anime.title }) == true)
        }
    }

    func testProviderIDsAreUniqueAndNamesAreNotBlank() {
        let providers = AnimeWebsiteProvider.supported
        XCTAssertEqual(Set(providers.map(\.id)).count, providers.count)
        XCTAssertTrue(providers.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testSearchURLDoesNotAcceptNonHTTPSProviderBase() {
        let provider = AnimeWebsiteProvider(
            id: "unsafe",
            name: "Unsafe",
            searchBaseURL: URL(string: "http://example.com/search")!,
            queryParameter: "query"
        )
        let anime = AnimeTitle(
            id: 1,
            title: "Test",
            nativeTitle: nil,
            synopsis: "",
            episodeCount: nil,
            seasonYear: nil,
            averageRating: nil,
            coverURL: nil,
            genres: [],
            format: nil,
            status: nil
        )
        XCTAssertNil(provider.searchURL(for: anime))
    }
}
