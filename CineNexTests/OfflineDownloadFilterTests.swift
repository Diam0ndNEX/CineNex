import XCTest
@testable import CineNex

final class OfflineDownloadFilterTests: XCTestCase {
    private func download(_ status: OfflineDownloadStatus, id: String) -> OfflineDownload {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        return OfflineDownload(
            id: id,
            title: id,
            sourceURL: URL(string: "https://media.example.org/\(id).m3u8")!,
            createdAt: date,
            updatedAt: date,
            status: status,
            progress: status == .completed ? 1 : 0.25,
            localDirectoryName: status == .completed ? "\(id).movpkg" : nil,
            errorMessage: nil
        )
    }

    func testAllFilterIncludesEveryDownloadStatus() {
        let downloads = [
            download(.queued, id: "queued"),
            download(.downloading, id: "downloading"),
            download(.paused, id: "paused"),
            download(.completed, id: "completed"),
            download(.failed, id: "failed"),
            download(.cancelled, id: "cancelled")
        ]

        XCTAssertTrue(downloads.allSatisfy(OfflineDownloadFilter.all.includes))
    }

    func testSavedFilterIncludesOnlyCompletedDownloads() {
        XCTAssertTrue(OfflineDownloadFilter.saved.includes(download(.completed, id: "completed")))
        XCTAssertFalse(OfflineDownloadFilter.saved.includes(download(.queued, id: "queued")))
        XCTAssertFalse(OfflineDownloadFilter.saved.includes(download(.failed, id: "failed")))
    }

    func testActiveFilterIncludesQueuedDownloadingAndPausedDownloads() {
        for status in [OfflineDownloadStatus.queued, .downloading, .paused] {
            XCTAssertTrue(OfflineDownloadFilter.active.includes(download(status, id: status.rawValue)))
        }

        for status in [OfflineDownloadStatus.completed, .failed, .cancelled] {
            XCTAssertFalse(OfflineDownloadFilter.active.includes(download(status, id: status.rawValue)))
        }
    }

    func testIssuesFilterIncludesFailedAndCancelledDownloads() {
        XCTAssertTrue(OfflineDownloadFilter.issues.includes(download(.failed, id: "failed")))
        XCTAssertTrue(OfflineDownloadFilter.issues.includes(download(.cancelled, id: "cancelled")))

        for status in [OfflineDownloadStatus.queued, .downloading, .paused, .completed] {
            XCTAssertFalse(OfflineDownloadFilter.issues.includes(download(status, id: status.rawValue)))
        }
    }
}
