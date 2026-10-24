import Foundation

protocol PlaybackExternalIDResolving: Sendable {
    func imdbID(for request: PlaybackSourceRequest) async throws -> String?
}

struct TMDBExternalIDResolver: PlaybackExternalIDResolving, Sendable {
    private let readAccessToken: String
    private let session: URLSession

    init(readAccessToken: String, session: URLSession = .shared) {
        self.readAccessToken = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func imdbID(for request: PlaybackSourceRequest) async throws -> String? {
        guard request.isValid, let tmdbID = request.tmdbID, tmdbID > 0 else { return nil }
        guard !readAccessToken.isEmpty else { throw TMDBCatalogError.missingToken }
        let mediaType = request.mediaKind == .movie ? "movie" : "tv"
        guard let url = URL(string: "https://api.themoviedb.org/3/\(mediaType)/\(tmdbID)/external_ids") else {
            throw TMDBCatalogError.invalidURL
        }
        var networkRequest = URLRequest(url: url)
        networkRequest.setValue("Bearer \(readAccessToken)", forHTTPHeaderField: "Authorization")
        networkRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        networkRequest.timeoutInterval = 12

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: networkRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TMDBCatalogError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw TMDBCatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw TMDBCatalogError.unauthorized }
            if http.statusCode == 429 { throw TMDBCatalogError.rateLimited }
            throw TMDBCatalogError.server(http.statusCode)
        }

        let responseBody: TMDBExternalIDsResponse
        do {
            responseBody = try JSONDecoder().decode(TMDBExternalIDsResponse.self, from: data)
        } catch {
            throw TMDBCatalogError.invalidData
        }
        guard let value = responseBody.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }
}

private struct TMDBExternalIDsResponse: Decodable {
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
}

struct StremioAddonPlaybackProvider: PlaybackSourceProvider, Sendable {
    let id: String
    let displayName: String
    let priority: Int
    private let clients: [StremioAddonClient]
    private let externalIDResolver: any PlaybackExternalIDResolving
    init(
        id: String = "stremio-addons",
        displayName: String = "Stremio-compatible add-ons",
        priority: Int = 50,
        manifestURLs: [URL],
        externalIDResolver: any PlaybackExternalIDResolving,
        session: URLSession = .shared
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StremioAddonClientError.invalidRequest
        }
        self.id = id
        self.displayName = displayName
        self.priority = priority
        self.clients = try manifestURLs.map { try StremioAddonClient(manifestURL: $0, session: session) }
        self.externalIDResolver = externalIDResolver
    }

    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource] {
        try Task.checkCancellation()
        guard request.isValid else { throw StremioAddonClientError.invalidRequest }
        guard !clients.isEmpty else { return [] }
        let resolvedIMDbID = try await externalIDResolver.imdbID(for: request)
        try Task.checkCancellation()
        guard let imdbID = resolvedIMDbID else {
            return []
        }

        let streamRequest = StremioStreamRequest(
            mediaType: request.mediaKind == .movie ? "movie" : "series",
            itemID: imdbID,
            seasonNumber: request.seasonNumber,
            episodeNumber: request.episodeNumber
        )
        if clients.count == 1 {
            let entries = try await clients[0].fetchStreams(for: streamRequest)
            return Self.mapSources(
                entries,
                index: 0,
                providerID: id,
                displayName: displayName,
                priority: priority
            )
        }

        let aggregated = try await withThrowingTaskGroup(
            of: (sources: [PlaybackSource], failure: String?).self,
            returning: (sources: [PlaybackSource], failures: [String]).self
        ) { group in
            for (index, client) in clients.enumerated() {
                group.addTask { () -> (sources: [PlaybackSource], failure: String?) in
                    do {
                        let entries = try await client.fetchStreams(for: streamRequest)
                        let sources = Self.mapSources(
                            entries,
                            index: index,
                            providerID: id,
                            displayName: displayName,
                            priority: priority
                        )
                        return (sources, nil)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        return ([], error.localizedDescription)
                    }
                }
            }
            var sources: [PlaybackSource] = []
            var failures: [String] = []
            for try await result in group {
                sources.append(contentsOf: result.sources)
                if let failure = result.failure { failures.append(failure) }
            }
            return (sources, failures)
        }
        if aggregated.sources.isEmpty, !aggregated.failures.isEmpty {
            throw StremioAddonClientError.transport(aggregated.failures.joined(separator: " "))
        }
        return aggregated.sources
    }

    private static func mapSources(
        _ entries: [StremioStreamEntry],
        index: Int,
        providerID: String,
        displayName: String,
        priority: Int
    ) -> [PlaybackSource] {
        entries.compactMap { entry -> PlaybackSource? in
            guard let url = entry.validatedPlaybackURL else { return nil }
            let title = [entry.name, entry.title]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "Stream from add-on \(index + 1)"
            let quality = Self.qualityLabel(from: [entry.name, entry.title, entry.description].compactMap { $0 }.joined(separator: " "))
            return PlaybackSource(
                id: "stremio-\(index)-\(url.absoluteString)",
                providerID: providerID,
                providerName: displayName,
                title: title,
                url: url,
                qualityLabel: quality,
                languageCode: nil,
                subtitleLanguages: [],
                supportsNativePlayback: Self.supportsNativePlayback(url),
                providerPriority: priority
            )
        }
    }

    private static func supportsNativePlayback(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".m3u8", ".mp4", ".m4v", ".mov", ".mp3", ".m4a"].contains { path.hasSuffix($0) }
    }

    private static func qualityLabel(from text: String) -> String? {
        let uppercased = text.uppercased()
        for label in ["2160P", "4K", "1080P", "720P", "480P", "SD", "HD"] where uppercased.contains(label) {
            return label
        }
        return nil
    }
}
