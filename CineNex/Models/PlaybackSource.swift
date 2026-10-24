import Foundation

enum PlaybackMediaKind: String, Codable, Equatable, Sendable {
    case movie
    case series
}

struct PlaybackSourceRequest: Codable, Equatable, Sendable {
    let title: String
    let mediaKind: PlaybackMediaKind
    let tmdbID: Int?
    let releaseYear: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?

    init(
        title: String,
        mediaKind: PlaybackMediaKind,
        tmdbID: Int? = nil,
        releaseYear: Int? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mediaKind = mediaKind
        self.tmdbID = tmdbID
        self.releaseYear = releaseYear
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    var isValid: Bool {
        !title.isEmpty
            && (tmdbID == nil || tmdbID! > 0)
            && (releaseYear == nil || releaseYear! > 0)
            && (seasonNumber == nil || seasonNumber! >= 0)
            && (episodeNumber == nil || episodeNumber! > 0)
            && (mediaKind == .series || (seasonNumber == nil && episodeNumber == nil))
            && ((seasonNumber == nil) == (episodeNumber == nil))
    }
}

struct PlaybackSource: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let providerName: String
    let title: String
    let url: URL
    let qualityLabel: String?
    let languageCode: String?
    let subtitleLanguages: [String]
    let supportsNativePlayback: Bool
    let providerPriority: Int

    var hasSecureWebURL: Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "https"
    }

    var isValid: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http")
            && url.host != nil
    }
}

protocol PlaybackSourceProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var priority: Int { get }
    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource]
}

struct PlaybackProviderFailure: Equatable, Sendable {
    let providerID: String
    let providerName: String
    let message: String
}

struct PlaybackSourceSearchResult: Equatable, Sendable {
    let sources: [PlaybackSource]
    let failures: [PlaybackProviderFailure]
    let providersQueried: Int

    var hasSources: Bool { !sources.isEmpty }
}

enum PlaybackSourceSearchError: LocalizedError {
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Choose a valid movie or a specific series episode before searching playback sources."
        }
    }
}

struct PlaybackSourceCoordinator: Sendable {
    let providers: [any PlaybackSourceProvider]

    init(providers: [any PlaybackSourceProvider]) {
        var seen = Set<String>()
        self.providers = providers.filter { provider in
            let cleanID = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            return !cleanID.isEmpty && seen.insert(cleanID).inserted
        }
    }

    func search(for request: PlaybackSourceRequest) async throws -> PlaybackSourceSearchResult {
        guard request.isValid else {
            throw PlaybackSourceSearchError.invalidRequest
        }

        let providers = self.providers
        let results = await withTaskGroup(of: ProviderSearchResult.self, returning: [ProviderSearchResult].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let sources = try await provider.findSources(for: request)
                        return ProviderSearchResult(
                            providerID: provider.id,
                            providerName: provider.displayName,
                            providerPriority: provider.priority,
                            sources: sources,
                            failure: nil
                        )
                    } catch {
                        return ProviderSearchResult(
                            providerID: provider.id,
                            providerName: provider.displayName,
                            providerPriority: provider.priority,
                            sources: [],
                            failure: PlaybackProviderFailure(
                                providerID: provider.id,
                                providerName: provider.displayName,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            }

            var collected: [ProviderSearchResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        var uniqueSources: [String: PlaybackSource] = [:]
        var failures: [PlaybackProviderFailure] = []

        for result in results {
            if let failure = result.failure {
                failures.append(failure)
            }
            for var source in result.sources where source.isValid {
                if source.providerID != result.providerID {
                    source = PlaybackSource(
                        id: source.id,
                        providerID: result.providerID,
                        providerName: result.providerName,
                        title: source.title,
                        url: source.url,
                        qualityLabel: source.qualityLabel,
                        languageCode: source.languageCode,
                        subtitleLanguages: source.subtitleLanguages,
                        supportsNativePlayback: source.supportsNativePlayback,
                        providerPriority: result.providerPriority
                    )
                }

                let key = source.url.absoluteURL.standardized.absoluteString
                if let existing = uniqueSources[key] {
                    if Self.precedes(source, existing) {
                        uniqueSources[key] = source
                    }
                } else {
                    uniqueSources[key] = source
                }
            }
        }

        let sortedSources = uniqueSources.values.sorted(by: Self.precedes)
        failures.sort { $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending }

        return PlaybackSourceSearchResult(
            sources: sortedSources,
            failures: failures,
            providersQueried: providers.count
        )
    }

    private static func precedes(_ lhs: PlaybackSource, _ rhs: PlaybackSource) -> Bool {
        if lhs.providerPriority != rhs.providerPriority {
            return lhs.providerPriority > rhs.providerPriority
        }
        if lhs.supportsNativePlayback != rhs.supportsNativePlayback {
            return lhs.supportsNativePlayback
        }
        if lhs.providerID != rhs.providerID {
            return lhs.providerID.localizedStandardCompare(rhs.providerID) == .orderedAscending
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}

private struct ProviderSearchResult: Sendable {
    let providerID: String
    let providerName: String
    let providerPriority: Int
    let sources: [PlaybackSource]
    let failure: PlaybackProviderFailure?
}
