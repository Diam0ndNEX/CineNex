import XCTest
@testable import CineNex

final class AniListCatalogProviderTests: XCTestCase {
    func testMapResponseMapsAnimeMetadataAndCleansDescription() throws {
        let json = """
        {
          "data": {
            "Page": {
              "media": [
                {
                  "id": 21,
                  "title": {
                    "romaji": "Kimi no Na wa",
                    "english": "Your Name",
                    "native": "君の名は。"
                  },
                  "description": "A <i>beautiful</i> story &amp; more. ~!hidden spoiler!~ After that.",
                  "episodes": 1,
                  "seasonYear": 2016,
                  "averageScore": 86,
                  "coverImage": {
                    "large": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21-abc.jpg"
                  },
                  "genres": ["Drama", "Romance", "Drama", ""],
                  "format": "MOVIE",
                  "status": "FINISHED"
                }
              ]
            }
          }
        }
        """

        let items = try AniListCatalogProvider.mapResponse(Data(json.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, 21)
        XCTAssertEqual(items[0].title, "Your Name")
        XCTAssertEqual(items[0].nativeTitle, "君の名は。")
        XCTAssertEqual(items[0].synopsis, "A beautiful story & more. After that.")
        XCTAssertEqual(items[0].episodeCount, 1)
        XCTAssertEqual(items[0].seasonYear, 2016)
        XCTAssertEqual(items[0].averageRating, 8.6)
        XCTAssertEqual(items[0].coverURL?.scheme, "https")
        XCTAssertEqual(items[0].genres, ["Drama", "Romance"])
        XCTAssertEqual(items[0].format, "MOVIE")
        XCTAssertEqual(items[0].status, "FINISHED")
    }

    func testMapResponseFallsBackToRomajiAndDropsDuplicatesAndInvalidEntries() throws {
        let json = """
        {
          "data": {
            "Page": {
              "media": [
                {
                  "id": 7,
                  "title": { "romaji": "Fallback Title", "english": " " },
                  "coverImage": { "large": "http://insecure.example/cover.jpg" },
                  "episodes": 0,
                  "seasonYear": -1,
                  "averageScore": 101
                },
                {
                  "id": 7,
                  "title": { "english": "Duplicate" }
                },
                {
                  "id": 8,
                  "title": { "english": "   ", "romaji": " " }
                },
                {
                  "id": 8,
                  "title": { "english": "Valid Duplicate After Bad Entry" }
                },
                {
                  "id": 0,
                  "title": { "english": "Invalid ID" }
                }
              ]
            }
          }
        }
        """

        let items = try AniListCatalogProvider.mapResponse(Data(json.utf8))

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Fallback Title")
        XCTAssertEqual(items[1].title, "Valid Duplicate After Bad Entry")
        XCTAssertNil(items[0].coverURL)
        XCTAssertNil(items[0].episodeCount)
        XCTAssertNil(items[0].seasonYear)
        XCTAssertNil(items[0].averageRating)
    }

    func testMapResponseRejectsMalformedJSON() {
        XCTAssertThrowsError(try AniListCatalogProvider.mapResponse(Data("{ invalid".utf8))) { error in
            guard case AniListCatalogError.invalidData = error else {
                XCTFail("Expected invalidData, got \(error)")
                return
            }
        }
    }


    func testSearchAnimeRejectsBlankQueryBeforeNetworking() async {
        do {
            _ = try await AniListCatalogProvider().searchAnime(query: "   ")
            XCTFail("Expected emptyQuery for a blank search")
        } catch {
            guard case AniListCatalogError.emptyQuery = error else {
                XCTFail("Expected emptyQuery, got \\(error)")
                return
            }
        }
    }

    func testFetchTrendingRejectsInvalidPageBeforeNetworking() async {
        do {
            _ = try await AniListCatalogProvider().fetchTrending(page: 0)
            XCTFail("Expected invalidPagination for page zero")
        } catch {
            guard case AniListCatalogError.invalidPagination = error else {
                XCTFail("Expected invalidPagination, got \\(error)")
                return
            }
        }
    }

    func testFetchTrendingRejectsPageSizesOutsideSupportedRange() async {
        for pageSize in [0, 51] {
            do {
                _ = try await AniListCatalogProvider().fetchTrending(perPage: pageSize)
                XCTFail("Expected invalidPagination for page size \\(pageSize)")
            } catch {
                guard case AniListCatalogError.invalidPagination = error else {
                    XCTFail("Expected invalidPagination, got \\(error)")
                    return
                }
            }
        }
    }

    func testMapResponseReportsGraphQLFailureWithoutData() {
        let json = """
        {
          "errors": [
            { "message": "Query complexity limit exceeded." }
          ]
        }
        """

        XCTAssertThrowsError(try AniListCatalogProvider.mapResponse(Data(json.utf8))) { error in
            guard case AniListCatalogError.api("Query complexity limit exceeded.") = error else {
                XCTFail("Expected GraphQL API error, got \(error)")
                return
            }
        }
    }
}
