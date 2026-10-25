import XCTest
@testable import CineNex

final class TorrentPlaybackProviderTests: XCTestCase {
    private enum StubFailure: Error {
        case preparationFailed
    }

    private actor StubEngine: TorrentPlaybackEngine {
        enum ResultMode: Sendable {
            case failure
            case empty
        }

        private let mode: ResultMode
        private var didStop = false

        init(mode: ResultMode) {
            self.mode = mode
        }

        func prepareFiles(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile] {
            switch mode {
            case .failure:
                throw StubFailure.preparationFailed
            case .empty:
                return []
            }
        }

        func stop() async {
            didStop = true
        }

        func stopWasCalled() -> Bool {
            didStop
        }
    }

    func testStopsEngineWhenPreparationFails() async throws {
        let engine = StubEngine(mode: .failure)
        let provider = TorrentPlaybackProvider(engine: engine)
        let request = PlaybackSourceRequest(title: "Example", mediaKind: .movie, tmdbID: 42)

        do {
            _ = try await provider.findSources(for: request)
            XCTFail("Preparation failure should be propagated.")
        } catch StubFailure.preparationFailed {
            let stopped = await engine.stopWasCalled()
            XCTAssertTrue(stopped)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStopsEngineWhenNoValidFilesArePrepared() async throws {
        let engine = StubEngine(mode: .empty)
        let provider = TorrentPlaybackProvider(engine: engine)
        let request = PlaybackSourceRequest(title: "Example", mediaKind: .movie, tmdbID: 42)

        let sources = try await provider.findSources(for: request)

        XCTAssertTrue(sources.isEmpty)
        let stopped = await engine.stopWasCalled()
        XCTAssertTrue(stopped)
    }
}
