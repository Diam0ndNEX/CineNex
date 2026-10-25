import Foundation

struct CinemetaCatalogProvider: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCatalog() async throws -> [MediaItem] {
        async let movieTask = fetchMetadata(type: "movie", query: nil)
        async let seriesTask = fetchMetadata(type: "series", query: nil)
        let movies = (try? await movieTask) ?? []
        let series = (try? await seriesTask) ?? []
        let combined = Self.uniqueItems(movies + series)
        guard !combined.isEmpty else {
            throw CinemetaCatalogError.noResults
        }
        return combined
    }

    func search(query: String) async throws -> [MediaItem] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return [] }
        async let movieTask = fetchMetadata(type: "movie", query: cleanedQuery)
        async let seriesTask = fetchMetadata(type: "series", query: cleanedQuery)
        let movies = (try? await movieTask) ?? []
        let series = (try? await seriesTask) ?? []
        return Self.uniqueItems(movies + series)
    }

    private func fetchMetadata(type: String, query: String?) async throws -> [MediaItem] {
        guard type == "movie" || type == "series" else {
            throw CinemetaCatalogError.invalidRequest
        }
        let searchPath: String
        if let query {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw CinemetaCatalogError.invalidRequest
            }
            searchPath = "/search=\(encodedQuery)"
        } else {
            searchPath = ""
        }
        guard let url = URL(string: "https://v3-cinemeta.strem.io/catalog/\(type)/top\(searchPath).json"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "v3-cinemeta.strem.io" else {
            throw CinemetaCatalogError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw CinemetaCatalogError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.scheme == "https",
              let finalHost = http.url?.host?.lowercased(),
              ["v3-cinemeta.strem.io", "cinemeta-catalogs.strem.io"].contains(finalHost),
              data.count <= 2_000_000 else {
            throw CinemetaCatalogError.invalidResponse
        }

        let decoded: CinemetaCatalogResponse
        do {
            decoded = try JSONDecoder().decode(CinemetaCatalogResponse.self, from: data)
        } catch {
            throw CinemetaCatalogError.invalidResponse
        }

        return decoded.metas.compactMap { meta in
            guard meta.type == type,
                  let title = meta.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  meta.id.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil else {
                return nil
            }
            let kind: MediaKind = type == "movie" ? .movie : .series
            let year = meta.releaseInfo.flatMap { Int($0.prefix(4)) } ?? 0
            let genres = meta.genres?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
            let posterURL = meta.poster.flatMap(Self.validImageURL)
            let description = meta.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            return MediaItem(
                id: "cinemeta-\(meta.id)",
                title: title,
                kind: kind,
                year: year,
                genre: genres.isEmpty ? (kind == .movie ? "Movie" : "Series") : genres.joined(separator: " · "),
                synopsis: description.flatMap { $0.isEmpty ? nil : $0 } ?? "No description is available for this title yet.",
                symbol: kind == .movie ? "film" : "tv",
                runtime: kind == .movie ? "Movie" : "Series",
                streamURL: nil,
                posterURL: posterURL,
                rating: meta.imdbRating.flatMap { Double($0) },
                externalID: nil,
                metadataProvider: "cinemeta"
            )
        }
    }

    private static func validImageURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

    private static func uniqueItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

private struct CinemetaCatalogResponse: Decodable {
    let metas: [CinemetaCatalogMeta]
}

private struct CinemetaCatalogMeta: Decodable {
    let id: String
    let type: String
    let name: String?
    let poster: String?
    let description: String?
    let releaseInfo: String?
    let genres: [String]?
    let imdbRating: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imdbID = "imdb_id"
        case type
        case name
        case poster
        case description
        case releaseInfo
        case genres
        case imdbRating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let identifier = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .imdbID) else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cinemeta metadata has no IMDb identifier.")
            )
        }
        id = identifier
        type = try container.decode(String.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        poster = try container.decodeIfPresent(String.self, forKey: .poster)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        releaseInfo = try container.decodeIfPresent(String.self, forKey: .releaseInfo)
        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        imdbRating = try container.decodeIfPresent(String.self, forKey: .imdbRating)
    }
}

enum CinemetaCatalogError: LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case noResults
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The title search request is invalid."
        case .invalidResponse:
            return "Cinemeta returned an invalid or unsupported response."
        case .noResults:
            return "Cinemeta is temporarily unavailable and returned no catalog results."
        case .network(let message):
            return "Cinemeta could not be reached: \(message)"
        }
    }
}
