import XCTest
@testable import CineNex

final class MediaItemTests: XCTestCase {
    func testDemoCatalogContainsMoviesAndSeries() {
        let catalog = MediaItem.demoCatalog

        XCTAssertFalse(catalog.isEmpty)
        XCTAssertTrue(catalog.contains { $0.kind == .movie })
        XCTAssertTrue(catalog.contains { $0.kind == .series })
    }

    func testDemoCatalogIdentifiersAreUnique() {
        let identifiers = MediaItem.demoCatalog.map(\.id)

        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }

    func testPlayableSampleHasHTTPSURL() {
        let sample = MediaItem.demoCatalog.first { $0.id == "big-buck-bunny" }

        XCTAssertNotNil(sample?.streamURL)
        XCTAssertEqual(sample?.streamURL?.scheme, "https")
        XCTAssertEqual(sample?.streamURL?.host, "storage.googleapis.com")
    }

    func testCatalogItemsHaveNonemptyDisplayMetadata() {
        for item in MediaItem.demoCatalog {
            XCTAssertFalse(item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(item.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(item.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testNonPlayableDemoItemsDoNotClaimToHaveStreams() {
        let unavailableItems = MediaItem.demoCatalog.filter { $0.id != "big-buck-bunny" }

        XCTAssertFalse(unavailableItems.isEmpty)
        XCTAssertTrue(unavailableItems.allSatisfy { $0.streamURL == nil })
    }
    func testTMDBResponseMapsMovieAndSeriesMetadataWithoutPlayableSources() throws {
        let data = Data("""
        {
          "results": [
            {
              "id": 550,
              "media_type": "movie",
              "title": "Fight Club",
              "overview": "An insomniac office worker.",
              "release_date": "1999-10-15",
              "poster_path": "/poster.jpg",
              "vote_average": 8.4,
              "genre_ids": [18]
            },
            {
              "id": 1399,
              "media_type": "tv",
              "name": "Game of Thrones",
              "overview": "Noble families fight for control.",
              "first_air_date": "2011-04-17",
              "poster_path": "/series.jpg",
              "vote_average": 8.3,
              "genre_ids": [18]
            },
            {
              "id": 999,
              "media_type": "person",
              "name": "Ignored result"
            }
          ]
        }
        """.utf8)

        let catalog = try TMDBCatalogProvider.mapResponse(data)

        XCTAssertEqual(catalog.count, 2)
        XCTAssertEqual(catalog[0].id, "tmdb-movie-550")
        XCTAssertEqual(catalog[0].title, "Fight Club")
        XCTAssertEqual(catalog[0].kind, .movie)
        XCTAssertEqual(catalog[0].year, 1999)
        XCTAssertEqual(catalog[0].genre, "Drama")
        XCTAssertEqual(catalog[0].rating, 8.4)
        XCTAssertEqual(catalog[0].posterURL?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")
        XCTAssertNil(catalog[0].streamURL)
        XCTAssertEqual(catalog[1].id, "tmdb-tv-1399")
        XCTAssertEqual(catalog[1].kind, .series)
        XCTAssertEqual(catalog[1].year, 2011)
        XCTAssertNil(catalog[1].streamURL)
    }

    func testTMDBResponseSkipsMalformedAndUnsupportedEntries() throws {
        let data = Data("""
        {
          "results": [
            {"id": 1, "media_type": "movie", "title": "   "},
            {"id": 2, "media_type": "person", "name": "Person"},
            {"id": 3, "media_type": "tv", "name": "Series", "first_air_date": "unknown"}
          ]
        }
        """.utf8)

        let catalog = try TMDBCatalogProvider.mapResponse(data)

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog[0].title, "Series")
        XCTAssertEqual(catalog[0].year, 0)
        XCTAssertEqual(catalog[0].genre, "Series")
        XCTAssertNil(catalog[0].posterURL)
    }

    func testTMDBResponseRejectsInvalidJSON() {
        XCTAssertThrowsError(try TMDBCatalogProvider.mapResponse(Data("not-json".utf8)))
    }

    func testTMDBSearchResponseMapsMoviesAndSeriesAndSkipsPeople() throws {
        let data = Data("""
        {"results":[
          {"id":11,"media_type":"movie","title":"Arrival","release_date":"2016-11-11","genre_ids":[878],"vote_average":7.6},
          {"id":12,"media_type":"tv","name":"Severance","first_air_date":"2022-02-18","genre_ids":[9648],"vote_average":8.7},
          {"id":13,"media_type":"person","name":"Ignored"}
        ]}
        """.utf8)
        let results = try TMDBCatalogProvider.mapResponse(data)
        XCTAssertEqual(results.map(\.title), ["Arrival", "Severance"])
        XCTAssertEqual(results.map(\.id), ["tmdb-movie-11", "tmdb-tv-12"])
        XCTAssertEqual(results[0].genre, "Sci-Fi")
        XCTAssertEqual(results[1].genre, "Mystery")
        XCTAssertTrue(results.allSatisfy { $0.streamURL == nil })
    }

    func testTMDBResponseDeduplicatesRepeatedIDs() throws {
        let data = Data("""
        {"results":[
          {"id":11,"media_type":"movie","title":"Arrival"},
          {"id":11,"media_type":"movie","title":"Arrival duplicate"}
        ]}
        """.utf8)
        let results = try TMDBCatalogProvider.mapResponse(data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Arrival")
    }

    func testTraktScrobblePayloadIncludesVerifiedTMDBIdentifier() {
        let item = MediaItem(
            id: "tmdb-movie-550",
            title: "Fight Club",
            kind: .movie,
            year: 1999,
            genre: "Drama",
            synopsis: "A test item.",
            symbol: "film",
            runtime: "Movie",
            streamURL: nil,
            externalID: 550,
            metadataProvider: "tmdb"
        )

        let payload = TraktScrobbleMetadata.moviePayload(for: item)

        XCTAssertEqual(payload["title"] as? String, "Fight Club")
        XCTAssertEqual(payload["year"] as? Int, 1999)
        let ids = payload["ids"] as? [String: Int]
        XCTAssertEqual(ids?["tmdb"], 550)
    }

    func testTraktScrobblePayloadDoesNotInventExternalIdentifiers() {
        let item = MediaItem(
            id: "big-buck-bunny",
            title: "Big Buck Bunny",
            kind: .movie,
            year: 2008,
            genre: "Animation",
            synopsis: "A test item.",
            symbol: "hare.fill",
            runtime: "10 min",
            streamURL: URL(string: "https://example.com/sample.mp4")
        )

        let payload = TraktScrobbleMetadata.moviePayload(for: item)

        XCTAssertNil(payload["ids"])
        XCTAssertEqual(payload["title"] as? String, "Big Buck Bunny")
        XCTAssertEqual(payload["year"] as? Int, 2008)
    }

}
