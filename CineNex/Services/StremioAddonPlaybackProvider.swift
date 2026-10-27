import Foundation

protocol PlaybackExternalIDResolving: Sendable {
    func imdbID(for request: PlaybackSourceRequest) async throws -> String?
}

struct TMDBExternalIDResolver: PlaybackExternalIDResolving, Sendable {
    private let readAccessToken: String
    private let session: URLSession

    init(readAccessToken: String, session: URLSession = SourceDiscoveryNetworking.session) {
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
        networkRequest.timeoutInterval = 5

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await SourceDiscoveryNetworking.data(for: networkRequest, session: session, timeout: 5)
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

struct CinemetaExternalIDResolver: PlaybackExternalIDResolving, Sendable {
    private let session: URLSession

    init(session: URLSession = SourceDiscoveryNetworking.session) {
        self.session = session
    }

    func imdbID(for request: PlaybackSourceRequest) async throws -> String? {
        if let existingID = request.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines),
           existingID.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil {
            return existingID
        }
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let catalogType = request.mediaKind == .movie ? "movie" : "series"
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw StremioAddonClientError.invalidRequest
        }
        let components = URLComponents(string: "https://v3-cinemeta.strem.io/catalog/\(catalogType)/top/search=\(encodedTitle).json")
        guard let url = components?.url,
              url.scheme == "https",
              url.host == "v3-cinemeta.strem.io" else {
            throw StremioAddonClientError.invalidRequest
        }

        var networkRequest = URLRequest(url: url)
        networkRequest.timeoutInterval = 5
        networkRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await SourceDiscoveryNetworking.data(for: networkRequest, session: session, timeout: 5)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw StremioAddonClientError.transport("Cinemeta title lookup failed: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.scheme == "https",
              let finalHost = http.url?.host?.lowercased(),
              ["v3-cinemeta.strem.io", "cinemeta-catalogs.strem.io"].contains(finalHost),
              data.count <= 1_000_000 else {
            throw StremioAddonClientError.invalidResponse
        }

        let catalog: CinemetaCatalogResponse
        do {
            catalog = try JSONDecoder().decode(CinemetaCatalogResponse.self, from: data)
        } catch {
            throw StremioAddonClientError.invalidResponse
        }

        let normalizedTitle = Self.normalized(title)
        let expectedType = request.mediaKind == .movie ? "movie" : "series"
        let exactMatches = catalog.metas.filter { meta in
            meta.type == expectedType
                && Self.normalized(meta.name) == normalizedTitle
                && meta.id.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil
        }
        guard !exactMatches.isEmpty else { return nil }

        if let releaseYear = request.releaseYear, releaseYear > 0 {
            let yearMatches = exactMatches.filter { meta in
                guard let releaseInfo = meta.releaseInfo,
                      let year = Int(releaseInfo.prefix(4)) else { return false }
                return year == releaseYear
            }
            if let match = yearMatches.first { return match.id }
            let yearUnknown = exactMatches.filter { meta in
                guard let releaseInfo = meta.releaseInfo else { return true }
                return Int(releaseInfo.prefix(4)) == nil
            }
            return yearUnknown.count == 1 ? yearUnknown.first?.id : nil
        }

        let uniqueIDs = Array(Set(exactMatches.map(\.id)))
        return uniqueIDs.count == 1 ? uniqueIDs.first : nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CinemetaCatalogResponse: Decodable {
    let metas: [CinemetaCatalogEntry]
}

private struct CinemetaCatalogEntry: Decodable {
    let id: String
    let type: String
    let name: String
    let releaseInfo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imdbID = "imdb_id"
        case type
        case name
        case releaseInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let identifier = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .imdbID) else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cinemeta entry has no IMDb identifier.")
            )
        }
        id = identifier
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        releaseInfo = try container.decodeIfPresent(String.self, forKey: .releaseInfo)
    }
}

struct AutomaticExternalIDResolver: PlaybackExternalIDResolving, Sendable {
    private let tmdbReadAccessToken: String?
    private let session: URLSession
    private let identifierCache: SourceIdentifierCache?

    init(tmdbReadAccessToken: String?, session: URLSession = SourceDiscoveryNetworking.session, identifierCache: SourceIdentifierCache? = nil) {
        let token = tmdbReadAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tmdbReadAccessToken = token.flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
        self.identifierCache = identifierCache ?? (SourceDiscoveryNetworking.usesApplicationCache(session) ? .shared : nil)
    }

    func imdbID(for request: PlaybackSourceRequest) async throws -> String? {
        try Task.checkCancellation()
        // Catalogs already supply IMDb IDs for most titles. Never delay these behind a TMDB call.
        if let value = request.imdbID, value.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil { return value }
        if let identifierCache {
            // Episode coordinates do not change a series' IMDb ID.
            let key = "\(request.mediaKind.rawValue)|\(request.tmdbID.map(String.init) ?? "none")|\(request.releaseYear.map(String.init) ?? "none")|\(request.title)"
            return try await identifierCache.resolve(key: key) { try await self.lookup(request) }
        }
        return try await lookup(request)
    }

    private func lookup(_ request: PlaybackSourceRequest) async throws -> String? {
        PlaybackDiagnostics.record("discovery.identifier.begin", details: ["media_kind": request.mediaKind.rawValue])
        if let token = tmdbReadAccessToken {
            do {
                if let imdbID = try await TMDBExternalIDResolver(readAccessToken: token, session: session).imdbID(for: request) { return imdbID }
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        return try await CinemetaExternalIDResolver(session: session).imdbID(for: request)
    }
}

enum StremioAddonProviderOutcome: Equatable, Sendable {
    case found(directSourceCount: Int, torrentSourceCount: Int)
    case noSources
    case failed(String)
    case identifierUnavailable

    var summary: String {
        switch self {
        case let .found(directSourceCount, torrentSourceCount):
            return "found \(directSourceCount) direct / \(torrentSourceCount) torrent"
        case .noSources:
            return "no sources"
        case let .failed(message):
            return "failed: \(message)"
        case .identifierUnavailable:
            return "not queried: no matching IMDb ID"
        }
    }
}

struct StremioAddonProviderStatus: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let outcome: StremioAddonProviderOutcome

    var summary: String { "\(name): \(outcome.summary)" }
}

struct StremioAddonDiscovery: Equatable, Sendable {
    let sources: [PlaybackSource]
    let torrentDescriptors: [StremioTorrentDescriptor]
    let providerStatuses: [StremioAddonProviderStatus]
}

struct StremioAddonPlaybackProvider: PlaybackSourceProvider, Sendable {
    let id: String
    let displayName: String
    let priority: Int
    private let clients: [StremioAddonClient]
    private let clientDisplayNames: [String]
    private let externalIDResolver: any PlaybackExternalIDResolving
    init(
        id: String = "stremio-addons",
        displayName: String = "Stremio-compatible add-ons",
        priority: Int = 50,
        manifestURLs: [URL],
        externalIDResolver: any PlaybackExternalIDResolving,
        session: URLSession = SourceDiscoveryNetworking.session
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StremioAddonClientError.invalidRequest
        }
        self.id = id
        self.displayName = displayName
        self.priority = priority
        self.clients = try manifestURLs.map { try StremioAddonClient(manifestURL: $0, session: session) }
        self.clientDisplayNames = manifestURLs.map(Self.displayName(for:))
        self.externalIDResolver = externalIDResolver
    }

    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource] {
        let discovery = try await discover(for: request)
        if discovery.sources.isEmpty {
            let failures = discovery.providerStatuses.compactMap { status -> String? in
                if case .failed(let message) = status.outcome { return message }
                return nil
            }
            if !failures.isEmpty {
                throw StremioAddonClientError.transport(failures.joined(separator: " "))
            }
        }
        return discovery.sources
    }

    func discover(
        for request: PlaybackSourceRequest,
        onUpdate: (@Sendable (StremioAddonDiscovery) async -> Void)? = nil
    ) async throws -> StremioAddonDiscovery {
        guard request.isValid else { throw StremioAddonClientError.invalidRequest }
        guard !clients.isEmpty else {
            let empty = StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: [])
            if let onUpdate { await onUpdate(empty) }
            return empty
        }
        try Task.checkCancellation()
        let resolvedID: String?
        do {
            if let existing = request.imdbID { resolvedID = existing }
            else { resolvedID = try await externalIDResolver.imdbID(for: request) }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw CancellationError() }
            let statuses = clientDisplayNames.enumerated().map { index, name in
                StremioAddonProviderStatus(id: "\(index)-\(name.lowercased())", name: name, outcome: .failed(error.localizedDescription))
            }
            let failed = StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: statuses)
            if let onUpdate { await onUpdate(failed) }
            return failed
        }
        guard let imdbID = resolvedID else {
            let statuses = clientDisplayNames.enumerated().map { index, name in
                StremioAddonProviderStatus(
                    id: "\(index)-\(name.lowercased())",
                    name: name,
                    outcome: .identifierUnavailable
                )
            }
            let unavailable = StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: statuses)
            if let onUpdate { await onUpdate(unavailable) }
            return unavailable
        }

        let streamRequest = StremioStreamRequest(
            mediaType: request.mediaKind == .movie ? "movie" : "series",
            itemID: imdbID,
            seasonNumber: request.seasonNumber,
            episodeNumber: request.episodeNumber
        )
        var batches: [(index: Int, entries: [StremioStreamEntry])] = []
        var failuresByIndex: [Int: String] = [:]

        if clients.count == 1 {
            do {
                batches = [(0, try await clients[0].fetchStreams(for: streamRequest))]
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failuresByIndex[0] = error.localizedDescription
            }
            if let onUpdate {
                try Task.checkCancellation()
                await onUpdate(try makeDiscovery(batches: batches, failuresByIndex: failuresByIndex, completedIndices: [0]))
            }
        } else {
            let aggregated = await withTaskGroup(
                of: (index: Int, entries: [StremioStreamEntry], failure: String?).self,
                returning: (batches: [(index: Int, entries: [StremioStreamEntry])], failuresByIndex: [Int: String]).self
            ) { group in
                let maximumConcurrentRequests = 4
                var nextIndex = 0
                while nextIndex < min(maximumConcurrentRequests, clients.count) {
                    let index = nextIndex
                    let client = clients[index]
                    group.addTask { await Self.fetch(client, index: index, request: streamRequest) }
                    nextIndex += 1
                }
                var fetched: [(index: Int, entries: [StremioStreamEntry])] = []
                var errorsByIndex: [Int: String] = [:]
                for await result in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    if nextIndex < clients.count {
                        let index = nextIndex
                        let client = clients[index]
                        group.addTask { await Self.fetch(client, index: index, request: streamRequest) }
                        nextIndex += 1
                    }
                    if let failure = result.failure {
                        errorsByIndex[result.index] = failure
                    } else {
                        fetched.append((result.index, result.entries))
                    }
                    if let onUpdate {
                        let partial = try? makeDiscovery(
                            batches: result.failure == nil ? [(result.index, result.entries)] : [],
                            failuresByIndex: result.failure.map { [result.index: $0] } ?? [:],
                            completedIndices: [result.index])
                        if let partial, !Task.isCancelled { await onUpdate(partial) }
                    }
                }
                return (fetched, errorsByIndex)
            }
            batches = aggregated.batches
            failuresByIndex = aggregated.failuresByIndex
        }

        try Task.checkCancellation()

        return try makeDiscovery(batches: batches, failuresByIndex: failuresByIndex)
    }

    private func makeDiscovery(
        batches unsortedBatches: [(index: Int, entries: [StremioStreamEntry])],
        failuresByIndex: [Int: String],
        completedIndices: Set<Int>? = nil
    ) throws -> StremioAddonDiscovery {
        let batches = unsortedBatches.sorted { $0.index < $1.index }
        let mappingStarted = Date()
        var sources: [PlaybackSource] = []
        var descriptors: [StremioTorrentDescriptor] = []
        var countsByIndex: [Int: (direct: Int, torrents: Int)] = [:]
        var seenDescriptors = Set<String>()
        for batch in batches {
            try Task.checkCancellation()
            let name = clientDisplayNames.indices.contains(batch.index) ? clientDisplayNames[batch.index] : displayName
            let direct = Self.mapSources(batch.entries, index: batch.index, providerID: id, displayName: name, priority: priority)
            let torrents = batch.entries.compactMap { StremioTorrentDescriptor(stream: $0, providerName: name) }
            countsByIndex[batch.index] = (direct.count, torrents.count)
            sources.append(contentsOf: direct)
            descriptors.append(contentsOf: torrents.filter { seenDescriptors.insert($0.id).inserted })
        }
        PlaybackDiagnostics.record("addon.mapping.complete", details: [
            "elapsed_ms": String(Int(Date().timeIntervalSince(mappingStarted) * 1_000)),
            "torrent_count": String(descriptors.count), "direct_count": String(sources.count),
        ])

        let providerStatuses = clientDisplayNames.enumerated().filter { index, _ in
            completedIndices?.contains(index) ?? true
        }.map { index, name in
            let statusID = "\(index)-\(name.lowercased())"
            if let failure = failuresByIndex[index] {
                return StremioAddonProviderStatus(id: statusID, name: name, outcome: .failed(failure))
            }
            let directCount = countsByIndex[index]?.direct ?? 0
            let torrentCount = countsByIndex[index]?.torrents ?? 0
            if directCount + torrentCount > 0 {
                return StremioAddonProviderStatus(
                    id: statusID,
                    name: name,
                    outcome: .found(directSourceCount: directCount, torrentSourceCount: torrentCount)
                )
            }
            return StremioAddonProviderStatus(id: statusID, name: name, outcome: .noSources)
        }
        return StremioAddonDiscovery(
            sources: sources,
            torrentDescriptors: descriptors,
            providerStatuses: providerStatuses
        )
    }

    private static func fetch(
        _ client: StremioAddonClient, index: Int, request: StremioStreamRequest
    ) async -> (index: Int, entries: [StremioStreamEntry], failure: String?) {
        do { return (index, try await client.fetchStreams(for: request), nil) }
        catch is CancellationError { return (index, [], "Request cancelled.") }
        catch { return (index, [], error.localizedDescription) }
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
            let title = [entry.title, entry.name]
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

    private static func displayName(for manifestURL: URL) -> String {
        let host = (manifestURL.host ?? "").lowercased()
        if host.contains("torrentio") { return "Torrentio" }
        if host.contains("mediafusion") {
            if host.contains("midnightignite") { return "MediaFusion Midnight" }
            if host.contains("elfhosted") { return "MediaFusion ElfHosted" }
            return "MediaFusion · " + host
        }
        let label = host.split(separator: ".").first.map(String.init) ?? "External add-on"
        return label.replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.capitalized }
            .joined(separator: " ")
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
