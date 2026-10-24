import XCTest
@testable import CineNex

final class PlaybackSourceCoordinatorTests: XCTestCase {
    func testRequestRequiresTitleAndCompleteEpisodeCoordinates() {
        XCTAssertFalse(
            PlaybackSourceRequest(title: " ", mediaKind: .movie).isValid
        )
        XCTAssertFalse(
            PlaybackSourceRequest(
                title: "Example Series",
                mediaKind: .series,
                seasonNumber: 1
            ).isValid
        )
        XCTAssertFalse(
            PlaybackSourceRequest(
                title: "Example Movie",
                mediaKind: .movie,
                seasonNumber: 1,
                episodeNumber: 1
            ).isValid
        )
        XCTAssertTrue(
            PlaybackSourceRequest(
                title: "Example Series",
                mediaKind: .series,
                seasonNumber: 0,
                episodeNumber: 1
            ).isValid
        )
    }

    func testCoordinatorRejectsInvalidRequest() async {
        let coordinator = PlaybackSourceCoordinator(providers: [])
        do {
            _ = try await coordinator.search(
                for: PlaybackSourceRequest(title: "", mediaKind: .movie)
            )
            XCTFail("Expected invalid request error.")
        } catch {
            XCTAssertTrue(error is PlaybackSourceSearchError)
        }
    }

    func testCoordinatorDeduplicatesSourcesAndRanksResults() async throws {
        let sharedURL = URL(string: "https://media.example.test/movie.m3u8")!
        let lower = StubPlaybackProvider(
            id: "provider-low",
            name: "Low priority",
            priority: 1,
            sources: [
                makeSource(id: "low-copy", providerID: "provider-low", url: sharedURL, priority: 1),
                makeSource(id: "low-second", providerID: "provider-low", url: URL(string: "https://media.example.test/second.m3u8")!, priority: 1)
            ]
        )
        let higher = StubPlaybackProvider(
            id: "provider-high",
            name: "High priority",
            priority: 10,
            sources: [
                makeSource(id: "high-copy", providerID: "provider-high", url: sharedURL, priority: 10)
            ]
        )
        let coordinator = PlaybackSourceCoordinator(providers: [lower, higher])

        let result = try await coordinator.search(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie, tmdbID: 42)
        )

        XCTAssertEqual(result.providersQueried, 2)
        XCTAssertEqual(result.sources.count, 2)
        XCTAssertEqual(result.sources.first?.providerID, "provider-high")
        XCTAssertEqual(result.sources.first?.url, sharedURL)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testCoordinatorKeepsWorkingSourcesWhenOneProviderFails() async throws {
        let working = StubPlaybackProvider(
            id: "working",
            name: "Working provider",
            priority: 3,
            sources: [makeSource(id: "working-1", providerID: "working", url: URL(string: "https://media.example.test/movie.mp4")!, priority: 3)]
        )
        let failing = StubPlaybackProvider(
            id: "failing",
            name: "Failing provider",
            priority: 2,
            errorMessage: "Provider unavailable"
        )
        let result = try await PlaybackSourceCoordinator(providers: [working, failing]).search(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie)
        )

        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.failures.map(\.providerID), ["failing"])
        XCTAssertEqual(result.failures.first?.message, "Provider unavailable")
    }

    func testCoordinatorRejectsUnsafeAndMalformedSourceURLs() async throws {
        let provider = StubPlaybackProvider(
            id: "provider",
            name: "Provider",
            priority: 1,
            sources: [
                makeSource(id: "file", providerID: "provider", url: URL(string: "file:///tmp/movie.mp4")!, priority: 1),
                makeSource(id: "javascript", providerID: "provider", url: URL(string: "javascript:alert(1)")!, priority: 1),
                makeSource(id: "valid", providerID: "provider", url: URL(string: "https://media.example.test/movie.mp4")!, priority: 1)
            ]
        )
        let result = try await PlaybackSourceCoordinator(providers: [provider]).search(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie)
        )

        XCTAssertEqual(result.sources.map(\.id), ["valid"])
    }

    func testCoordinatorIgnoresDuplicateProviderIdentifiers() async throws {
        let first = StubPlaybackProvider(
            id: "duplicate",
            name: "First",
            priority: 1,
            sources: [makeSource(id: "first", providerID: "duplicate", url: URL(string: "https://media.example.test/first.mp4")!, priority: 1)]
        )
        let second = StubPlaybackProvider(
            id: "duplicate",
            name: "Second",
            priority: 9,
            sources: [makeSource(id: "second", providerID: "duplicate", url: URL(string: "https://media.example.test/second.mp4")!, priority: 9)]
        )
        let result = try await PlaybackSourceCoordinator(providers: [first, second]).search(
            for: PlaybackSourceRequest(title: "Example Film", mediaKind: .movie)
        )

        XCTAssertEqual(result.providersQueried, 1)
        XCTAssertEqual(result.sources.map(\.id), ["first"])
    }

    private func makeSource(
        id: String,
        providerID: String,
        url: URL,
        priority: Int
    ) -> PlaybackSource {
        PlaybackSource(
            id: id,
            providerID: providerID,
            providerName: providerID,
            title: "Example",
            url: url,
            qualityLabel: "HD",
            languageCode: "en",
            subtitleLanguages: ["en"],
            supportsNativePlayback: true,
            providerPriority: priority
        )
    }
}

private struct StubPlaybackProvider: PlaybackSourceProvider {
    let id: String
    let displayName: String
    let priority: Int
    var sources: [PlaybackSource] = []
    var errorMessage: String?

    init(
        id: String,
        name: String,
        priority: Int,
        sources: [PlaybackSource] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.displayName = name
        self.priority = priority
        self.sources = sources
        self.errorMessage = errorMessage
    }

    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource] {
        if let errorMessage {
            throw StubProviderError.unavailable(errorMessage)
        }
        return sources
    }
}

private enum StubProviderError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}
