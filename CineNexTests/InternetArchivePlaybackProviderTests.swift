import XCTest
@testable import CineNex

final class InternetArchivePlaybackProviderTests: XCTestCase {
    func testAcceptsPublicDomainAndAttributionLicensesOnly() {
        XCTAssertTrue(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/publicdomain/zero/1.0/"))
        XCTAssertTrue(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/licenses/by/4.0/"))
        XCTAssertTrue(InternetArchivePlaybackProvider.isAllowedLicense("https://creativecommons.org/licenses/by-sa/4.0/"))
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
            identifier: "example-film",
            request: PlaybackSourceRequest(title: "Example Film", mediaKind: .series, seasonNumber: 1, episodeNumber: 1)
        ).isEmpty)
    }
}
