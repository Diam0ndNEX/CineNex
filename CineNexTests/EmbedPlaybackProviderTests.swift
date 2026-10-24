import XCTest
@testable import CineNex

final class EmbedPlaybackProviderTests: XCTestCase {
    func testMovieURLUsesTMDBIdentifier() throws {
        let provider = EmbedPlaybackProvider(
            id: "test",
            displayName: "Test",
            baseURL: URL(string: "https://media.example.test/embed/")!,
            priority: 1
        )
        let url = try XCTUnwrap(provider.embedURL(
            for: PlaybackSourceRequest(title: "Example Movie", mediaKind: .movie, tmdbID: 42)
        ))
        XCTAssertEqual(url.absoluteString, "https://media.example.test/embed/movie/42")
    }

    func testSeriesRequiresSpecificEpisode() {
        let provider = EmbedPlaybackProvider(
            id: "test",
            displayName: "Test",
            baseURL: URL(string: "https://media.example.test/embed/")!,
            priority: 1
        )
        XCTAssertNil(provider.embedURL(
            for: PlaybackSourceRequest(title: "Example Series", mediaKind: .series, tmdbID: 42)
        ))
        XCTAssertEqual(
            provider.embedURL(
                for: PlaybackSourceRequest(
                    title: "Example Series",
                    mediaKind: .series,
                    tmdbID: 42,
                    seasonNumber: 2,
                    episodeNumber: 4
                )
            )?.absoluteString,
            "https://media.example.test/embed/tv/42/2/4"
        )
    }

    func testProviderRejectsMissingIdentifierAndNonHTTPSBaseURL() {
        let provider = EmbedPlaybackProvider(
            id: "test",
            displayName: "Test",
            baseURL: URL(string: "https://media.example.test/embed/")!,
            priority: 1
        )
        XCTAssertNil(provider.embedURL(
            for: PlaybackSourceRequest(title: "Example Movie", mediaKind: .movie)
        ))

        let unsafe = EmbedPlaybackProvider(
            id: "unsafe",
            displayName: "Unsafe",
            baseURL: URL(string: "http://media.example.test/embed/")!,
            priority: 1
        )
        XCTAssertNil(unsafe.embedURL(
            for: PlaybackSourceRequest(title: "Example Movie", mediaKind: .movie, tmdbID: 42)
        ))
    }
    func testTitleIdentifierIsEncodedAsSinglePathSegment() throws {
        let provider = EmbedPlaybackProvider(
            id: "test",
            displayName: "Test",
            baseURL: URL(string: "https://media.example.test/embed/")!,
            priority: 1,
            requiresTMDBID: false
        )
        let url = try XCTUnwrap(provider.embedURL(
            for: PlaybackSourceRequest(title: "../not/a/path", mediaKind: .movie)
        ))
        XCTAssertEqual(url.host, "media.example.test")
        XCTAssertTrue(url.path.contains("%2F") || url.path.contains("%252F"))
        XCTAssertFalse(url.path.contains("/not/a/path"))
    }
}
