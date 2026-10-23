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
