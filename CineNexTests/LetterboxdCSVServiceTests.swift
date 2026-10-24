import XCTest
@testable import CineNex

final class LetterboxdCSVServiceTests: XCTestCase {
    func testDiaryCSVParsesQuotedCommasAndRatings() throws {
        let csv = """
        Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date
        2026-01-02,"Film, The",2024,https://letterboxd.com/film/film-the/,4.5,Yes,"favourites, cinema",2026-01-01
        """
        let records = try LetterboxdCSVService.parse(csv, filename: "diary.csv")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].title, "Film, The")
        XCTAssertEqual(records[0].year, 2024)
        XCTAssertEqual(records[0].rating, 4.5)
        XCTAssertEqual(records[0].rewatch, true)
        XCTAssertEqual(records[0].tags, "favourites, cinema")
        XCTAssertEqual(records[0].watchedDate, "2026-01-01")
        XCTAssertEqual(records[0].kind, .diary)
    }

    func testCSVParserPreservesQuotedNewlinesAndEscapedQuotes() throws {
        let csv = """
        Date,Name,Year,Letterboxd URI,Rating,Review,Watched Date
        2026-01-02,"A ""Quoted""
        Film",2020,https://letterboxd.com/film/a-quoted-film/,3,"A review,
        with two lines",2026-01-01
        """
        let records = try LetterboxdCSVService.parse(csv, filename: "diary.csv")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].title, "A \"Quoted\"\nFilm")
        XCTAssertEqual(records[0].review, "A review,\nwith two lines")
    }

    func testDiaryExportUsesLetterboxdColumnsAndEscapesValues() throws {
        let record = LetterboxdRecord(
            id: "diary|film|2026-01-01",
            title: "Film, The",
            year: 2024,
            letterboxdURI: "https://letterboxd.com/film/film-the/",
            dateAdded: "2026-01-02",
            watchedDate: "2026-01-01",
            rating: 4.5,
            rewatch: false,
            tags: "favourites, cinema",
            review: nil,
            kind: .diary
        )
        let csv = LetterboxdCSVService.makeDiaryCSV(from: [record])

        XCTAssertTrue(csv.hasPrefix("Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date\r\n"))
        XCTAssertTrue(csv.contains("\"Film, The\""))
        XCTAssertTrue(csv.contains("\"favourites, cinema\""))
        XCTAssertTrue(csv.contains("4.5,No"))
    }

    func testEachSupportedRecordKindExportsItsOwnLetterboxdCSVFormat() {
        let records = [
            LetterboxdRecord(id: "diary-1", title: "Diary Film", year: 2024, letterboxdURI: "https://letterboxd.com/film/diary-film/", dateAdded: "2026-01-02", watchedDate: "2026-01-01", rating: 4.5, rewatch: true, tags: "favourites", review: "Great", kind: .diary),
            LetterboxdRecord(id: "watched-1", title: "Watched Film", year: 2023, letterboxdURI: "https://letterboxd.com/film/watched-film/", dateAdded: nil, watchedDate: "2026-02-01", rating: nil, rewatch: nil, tags: nil, review: nil, kind: .watched),
            LetterboxdRecord(id: "rating-1", title: "Rated Film", year: 2022, letterboxdURI: "https://letterboxd.com/film/rated-film/", dateAdded: "2026-03-01", watchedDate: nil, rating: 3.5, rewatch: nil, tags: nil, review: nil, kind: .ratings),
            LetterboxdRecord(id: "watchlist-1", title: "Watchlist Film", year: 2021, letterboxdURI: "https://letterboxd.com/film/watchlist-film/", dateAdded: "2026-04-01", watchedDate: nil, rating: nil, rewatch: nil, tags: nil, review: nil, kind: .watchlist)
        ]

        let watchedCSV = LetterboxdCSVService.makeCSV(from: records, kind: .watched)
        XCTAssertTrue(watchedCSV.hasPrefix("Date,Name,Year,Letterboxd URI\r\n"))
        XCTAssertTrue(watchedCSV.contains("2026-02-01,Watched Film,2023,"))
        XCTAssertFalse(watchedCSV.contains("Diary Film"))

        let ratingsCSV = LetterboxdCSVService.makeCSV(from: records, kind: .ratings)
        XCTAssertTrue(ratingsCSV.hasPrefix("Date,Name,Year,Letterboxd URI,Rating\r\n"))
        XCTAssertTrue(ratingsCSV.contains("2026-03-01,Rated Film,2022,"))
        XCTAssertTrue(ratingsCSV.contains(",3.5\r\n"))
        XCTAssertFalse(ratingsCSV.contains("Watchlist Film"))

        let watchlistCSV = LetterboxdCSVService.makeCSV(from: records, kind: .watchlist)
        XCTAssertTrue(watchlistCSV.hasPrefix("Date,Name,Year,Letterboxd URI\r\n"))
        XCTAssertTrue(watchlistCSV.contains("2026-04-01,Watchlist Film,2021,"))
        XCTAssertFalse(watchlistCSV.contains("Rated Film"))
    }

    func testCSVExportQuotesCommasAndNewlinesForWatchlistRecords() {
        let record = LetterboxdRecord(
            id: "watchlist-special",
            title: "Film, With a Line\nBreak",
            year: 2020,
            letterboxdURI: nil,
            dateAdded: "2026-04-01",
            watchedDate: nil,
            rating: nil,
            rewatch: nil,
            tags: nil,
            review: nil,
            kind: .watchlist
        )

        let csv = LetterboxdCSVService.makeCSV(from: [record], kind: .watchlist)
        XCTAssertTrue(csv.contains("\"Film, With a Line"))
        XCTAssertTrue(csv.contains("Break\""))
    }

    func testUnknownCSVWithoutTitleColumnFailsClearly() {
        XCTAssertThrowsError(try LetterboxdCSVService.parse("Date,Rating\n2026-01-01,4", filename: "unknown.csv"))
    }
    func testMalformedCSVWithUnfinishedQuotedFieldFailsClearly() {
        let csv = """
        Date,Name,Year
        2026-01-01,"Unfinished film,2020
        """

        XCTAssertThrowsError(try LetterboxdCSVService.parse(csv, filename: "diary.csv")) { error in
            guard case LetterboxdCSVError.malformedCSV = error else {
                XCTFail("Expected malformedCSV, got \\(error)")
                return
            }
        }
    }

    func testMalformedCSVWithQuoteInsideUnquotedFieldFailsClearly() {
        let csv = """
        Date,Name,Year
        2026-01-01,Film "Title",2020
        """

        XCTAssertThrowsError(try LetterboxdCSVService.parse(csv, filename: "diary.csv")) { error in
            guard case LetterboxdCSVError.malformedCSV = error else {
                XCTFail("Expected malformedCSV, got \\(error)")
                return
            }
        }
    }
}
