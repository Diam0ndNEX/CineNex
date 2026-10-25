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

struct CinemetaExternalIDResolver: PlaybackExternalIDResolving, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
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
        networkRequest.timeoutInterval = 10
        networkRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: networkRequest)
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

    init(tmdbReadAccessToken: String?, session: URLSession = .shared) {
        let token = tmdbReadAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tmdbReadAccessToken = token.flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
    }

    func imdbID(for request: PlaybackSourceRequest) async throws -> String? {
        if let token = tmdbReadAccessToken {
            do {
                if let imdbID = try await TMDBExternalIDResolver(readAccessToken: token, session: session).imdbID(for: request) {
                    return imdbID
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
            }
        }
        return try await CinemetaExternalIDResolver(session: session).imdbID(for: request)
    }
}

struct StremioAddonDiscovery: Equatable, Sendable {
    let sources: [PlaybackSource]
    let torrentDescriptors: [StremioTorrentDescriptor]
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
        self.clientDisplayNames = manifestURLs.map(Self.displayName(for:))
        self.externalIDResolver = externalIDResolver
    }

    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource] {
        try await discover(for: request).sources
    }

    func discover(for request: PlaybackSourceRequest) async throws -> StremioAddonDiscovery {
        guard request.isValid else { throw StremioAddonClientError.invalidRequest }
        guard !clients.isEmpty else { return StremioAddonDiscovery(sources: [], torrentDescriptors: []) }
        guard let imdbID = try await externalIDResolver.imdbID(for: request) else {
            return StremioAddonDiscovery(sources: [], torrentDescriptors: [])
        }

        let streamRequest = StremioStreamRequest(
            mediaType: request.mediaKind == .movie ? "movie" : "series",
            itemID: imdbID,
            seasonNumber: request.seasonNumber,
            episodeNumber: request.episodeNumber
        )
        var batches: [(index: Int, entries: [StremioStreamEntry])] = []
        var failures: [String] = []

        if clients.count == 1 {
            do {
                batches = [(0, try await clients[0].fetchStreams(for: streamRequest))]
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures = ["\(clientDisplayNames.first ?? displayName): \(error.localizedDescription)"]
            }
        } else {
            let aggregated = await withTaskGroup(
                of: (index: Int, entries: [StremioStreamEntry], failure: String?).self,
                returning: (batches: [(index: Int, entries: [StremioStreamEntry])], failures: [String]).self
            ) { group in
                for (index, client) in clients.enumerated() {
                    group.addTask {
                        do {
                            return (index, try await client.fetchStreams(for: streamRequest), nil)
                        } catch {
                            let providerName = clientDisplayNames.indices.contains(index) ? clientDisplayNames[index] : displayName
                            return (index, [], "\(providerName): \(error.localizedDescription)")
                        }
                    }
                }
                var fetched: [(index: Int, entries: [StremioStreamEntry])] = []
                var errors: [String] = []
                for await result in group {
                    if let failure = result.failure {
                        errors.append(failure)
                    } else {
                        fetched.append((result.index, result.entries))
                    }
                }
                return (fetched, errors)
            }
            batches = aggregated.batches
            failures = aggregated.failures
        }

        try Task.checkCancellation()

        batches.sort { $0.index < $1.index }
        let sources = batches.flatMap { batch in
            Self.mapSources(
                batch.entries,
                index: batch.index,
                providerID: id,
                displayName: clientDisplayNames.indices.contains(batch.index) ? clientDisplayNames[batch.index] : displayName,
                priority: priority
            )
        }
        var seenDescriptors = Set<String>()
        let descriptors = batches.flatMap { batch in
            let providerName = clientDisplayNames.indices.contains(batch.index) ? clientDisplayNames[batch.index] : displayName
            return batch.entries.compactMap {
                StremioTorrentDescriptor(stream: $0, providerName: providerName)
            }
        }.filter { descriptor in
            let providerKey = descriptor.providerName.lowercased()
            return seenDescriptors.insert("\(providerKey):\(descriptor.id)").inserted
        }

        if sources.isEmpty, descriptors.isEmpty, !failures.isEmpty {
            throw StremioAddonClientError.transport(failures.joined(separator: " "))
        }
        return StremioAddonDiscovery(sources: sources, torrentDescriptors: descriptors)
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
        if host.contains("mediafusion") { return "MediaFusion" }
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
