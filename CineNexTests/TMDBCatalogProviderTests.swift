import XCTest
@testable import CineNex

final class TMDBCatalogProviderTests: XCTestCase {
    func testMapResponseRejectsMalformedJSON() {
        XCTAssertThrowsError(try TMDBCatalogProvider.mapResponse(Data("{ invalid".utf8))) { error in
            guard case TMDBCatalogError.invalidData = error else {
                XCTFail("Expected invalidData, got \(error)")
                return
            }
        }
    }

    func testMapResponseDropsUnsupportedMediaTypesAndDuplicateIDs() throws {
        let json = """
        {
          "results": [
            {
              "id": 101,
              "media_type": "movie",
              "title": "Example Film",
              "release_date": "2024-05-16",
              "overview": "A sample overview.",
              "genre_ids": [18],
              "vote_average": 7.8
            },
            {
              "id": 101,
              "media_type": "movie",
              "title": "Duplicate Film"
            },
            {
              "id": 303,
              "media_type": "person",
              "name": "Unsupported Person"
            }
          ]
        }
        """
        let items = try TMDBCatalogProvider.mapResponse(Data(json.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "tmdb-movie-101")
        XCTAssertEqual(items.first?.title, "Example Film")
        XCTAssertEqual(items.first?.year, 2024)
        XCTAssertEqual(items.first?.genre, "Drama")
        XCTAssertEqual(items.first?.rating, 7.8)
    }

    func testMapSearchPageClampsResponsePageToTotalPages() throws {
        let json = """
        {
          "page": 9,
          "total_pages": 3,
          "results": [
            {
              "id": 501,
              "media_type": "movie",
              "title": "Paginated Film",
              "release_date": "2025-02-03",
              "genre_ids": [28]
            }
          ]
        }
        """
        let page = try TMDBCatalogProvider.mapSearchPage(Data(json.utf8), requestedPage: 8)
        XCTAssertEqual(page.items.map(\.title), ["Paginated Film"])
        XCTAssertEqual(page.page, 3)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertFalse(page.hasMorePages)
    }

    func testMapSearchPageRejectsNonPositiveRequestedPage() {
        XCTAssertThrowsError(
            try TMDBCatalogProvider.mapSearchPage(Data("{\"results\":[]}".utf8), requestedPage: 0)
        ) { error in
            guard case TMDBCatalogError.invalidURL = error else {
                XCTFail("Expected invalidURL, got \(error)")
                return
            }
        }
    }
}
