import XCTest
@testable import CineNex

final class TMDBGenreMappingTests: XCTestCase {
    func testMovieGenreMappingIncludesFamilyHistoryMusicTVMovieWarAndWestern() throws {
        let json = """
        {
          "results": [
            {"id": 1, "media_type": "movie", "title": "Family Film", "genre_ids": [10751]},
            {"id": 2, "media_type": "movie", "title": "History Film", "genre_ids": [36]},
            {"id": 3, "media_type": "movie", "title": "Music Film", "genre_ids": [10402]},
            {"id": 4, "media_type": "movie", "title": "TV Film", "genre_ids": [10770]},
            {"id": 5, "media_type": "movie", "title": "War Film", "genre_ids": [10752]},
            {"id": 6, "media_type": "movie", "title": "Western Film", "genre_ids": [37]}
          ]
        }
        """

        let items = try TMDBCatalogProvider.mapResponse(Data(json.utf8))

        XCTAssertEqual(items.map(\.genre), ["Family", "History", "Music", "TV Movie", "War", "Western"])
    }

    func testTVGenreMappingIncludesKidsNewsRealitySoapAndTalk() throws {
        let json = """
        {
          "results": [
            {"id": 11, "media_type": "tv", "name": "Kids Show", "genre_ids": [10762]},
            {"id": 12, "media_type": "tv", "name": "News Show", "genre_ids": [10763]},
            {"id": 13, "media_type": "tv", "name": "Reality Show", "genre_ids": [10764]},
            {"id": 14, "media_type": "tv", "name": "Soap Show", "genre_ids": [10766]},
            {"id": 15, "media_type": "tv", "name": "Talk Show", "genre_ids": [10767]}
          ]
        }
        """

        let items = try TMDBCatalogProvider.mapResponse(Data(json.utf8))

        XCTAssertEqual(items.map(\.genre), ["Kids", "News", "Reality", "Soap", "Talk"])
    }

    func testUnknownGenreUsesSafeMediaKindFallback() throws {
        let json = """
        {
          "results": [
            {"id": 21, "media_type": "movie", "title": "Unmapped Film", "genre_ids": [999999]},
            {"id": 22, "media_type": "tv", "name": "Unmapped Series", "genre_ids": [999999]}
          ]
        }
        """

        let items = try TMDBCatalogProvider.mapResponse(Data(json.utf8))

        XCTAssertEqual(items.map(\.genre), ["Movie", "Series"])
    }
}
