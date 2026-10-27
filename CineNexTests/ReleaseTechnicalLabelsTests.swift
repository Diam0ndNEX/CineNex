import XCTest
@testable import CineNex

final class ReleaseTechnicalLabelsTests: XCTestCase {
    func testReportsOneReleaseHintForEachTechnicalCategory() {
        XCTAssertEqual(ReleaseTechnicalLabels.labels(in: "Film.2160p.WEB-DL.DV.HDR10.x265.TrueHD.Atmos"),
                       ["HEVC", "Dolby Vision", "Atmos"])
        XCTAssertEqual(ReleaseTechnicalLabels.labels(in: "Film_1080p_AV1_HDR10+_EAC3"),
                       ["AV1", "HDR10+", "DD+"])
    }

    func testOrdinaryTitleWordsDoNotInventTechnicalDetails() {
        XCTAssertEqual(ReleaseTechnicalLabels.labels(in: "David and the Adventures of Tomorrow"), [])
        XCTAssertEqual(ReleaseTechnicalLabels.labels(in: "Film 1080p H.264 AAC"), ["H.264", "AAC"])
        XCTAssertEqual(ReleaseTechnicalLabels.labels(in: "No codec or audio metadata"), [])
    }
}
