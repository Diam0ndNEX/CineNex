import XCTest
@testable import CineNex

final class DetailCastArtworkTests: XCTestCase {
    func testCastProfileUsesReportedTMDBPathAndMissingPhotoStaysUnknown() throws {
        let member = try JSONDecoder().decode(TMDBTitleCastMember.self, from: Data(#"{"id":1,"name":"Actor","profile_path":"/portrait.jpg"}"#.utf8))
        XCTAssertEqual(member.profileURL?.absoluteString, "https://image.tmdb.org/t/p/w185/portrait.jpg")
        let absent = try JSONDecoder().decode(TMDBTitleCastMember.self, from: Data(#"{"id":2,"name":"Actor"}"#.utf8))
        XCTAssertNil(absent.profileURL)
        let invalid = try JSONDecoder().decode(TMDBTitleCastMember.self, from: Data(#"{"id":3,"profile_path":"https://another.test/photo"}"#.utf8))
        XCTAssertNil(invalid.profileURL)
    }
}
