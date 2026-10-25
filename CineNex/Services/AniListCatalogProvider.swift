import Foundation

struct AnimeTitle: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let nativeTitle: String?
    let synopsis: String
    let episodeCount: Int?
    let seasonYear: Int?
    let averageRating: Double?
    let coverURL: URL?
    let genres: [String]
    let format: String?
    let status: String?
}

struct AniListCatalogProvider {
    private static let endpoint = URL(string: "https://graphql.anilist.co")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTrending(page: Int = 1, perPage: Int = 20) async throws -> [AnimeTitle] {
        guard page > 0, (1...50).contains(perPage) else {
            throw AniListCatalogError.invalidPagination
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            AniListGraphQLRequest(
                query: Self.trendingQuery,
                variables: AniListVariables(page: page, perPage: perPage)
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AniListCatalogError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AniListCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw AniListCatalogError.rateLimited
            }
            throw AniListCatalogError.server(http.statusCode)
        }

        return try Self.mapResponse(data)
    }

    func searchAnime(query: String, page: Int = 1, perPage: Int = 20) async throws -> [AnimeTitle] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            throw AniListCatalogError.emptyQuery
        }
        guard page > 0, (1...50).contains(perPage) else {
            throw AniListCatalogError.invalidPagination
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            AniListGraphQLRequest(
                query: Self.searchQuery,
                variables: AniListVariables(page: page, perPage: perPage, search: cleanedQuery)
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AniListCatalogError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AniListCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw AniListCatalogError.rateLimited
            }
            throw AniListCatalogError.server(http.statusCode)
        }

        return try Self.mapResponse(data)
    }

    static func mapResponse(_ data: Data) throws -> [AnimeTitle] {
        let envelope: AniListEnvelope
        do {
            envelope = try JSONDecoder().decode(AniListEnvelope.self, from: data)
        } catch {
            throw AniListCatalogError.invalidData
        }

        if let firstError = envelope.errors?.first?.message,
           envelope.data?.page == nil {
            throw AniListCatalogError.api(firstError)
        }

        guard let results = envelope.data?.page?.media else {
            throw AniListCatalogError.invalidData
        }

        var seenIDs = Set<Int>()
        return results.compactMap { result -> AnimeTitle? in
            guard result.id > 0 else {
                return nil
            }

            let candidates = [result.title?.english, result.title?.romaji, result.title?.native]
            guard let title = candidates
                .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }),
                  seenIDs.insert(result.id).inserted else {
                return nil
            }

            let rawSynopsis = result.description ?? ""
            let withoutSpoilers = rawSynopsis.replacingOccurrences(
                of: "~!.*?!~",
                with: "",
                options: [.regularExpression, .dotMatchesLineSeparators]
            )
            let synopsis = withoutSpoilers
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#039;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")

            let score = result.averageScore.flatMap { (0...100).contains($0) ? Double($0) / 10 : nil }
            let coverURL = result.coverImage?.large.flatMap { value -> URL? in
                guard let url = URL(string: value),
                      url.scheme?.lowercased() == "https",
                      url.host != nil else {
                    return nil
                }
                return url
            }

            return AnimeTitle(
                id: result.id,
                title: title,
                nativeTitle: result.title?.native,
                synopsis: synopsis,
                episodeCount: result.episodes.flatMap { $0 > 0 ? $0 : nil },
                seasonYear: result.seasonYear.flatMap { $0 > 0 ? $0 : nil },
                averageRating: score,
                coverURL: coverURL,
                genres: (result.genres ?? []).reduce(into: [String]()) { genres, genre in
                    let cleaned = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && !genres.contains(cleaned) {
                        genres.append(cleaned)
                    }
                },
                format: result.format,
                status: result.status
            )
        }
    }

    private static let searchQuery = """
    query SearchAnime($page: Int!, $perPage: Int!, $search: String!) {
      Page(page: $page, perPage: $perPage) {
        media(type: ANIME, search: $search, sort: SEARCH_MATCH, isAdult: false) {
          id
          title {
            romaji
            english
            native
          }
          description(asHtml: false)
          episodes
          seasonYear
          averageScore
          coverImage {
            large
          }
          genres
          format
          status
        }
      }
    }
    """

    private static let trendingQuery = """
    query TrendingAnime($page: Int!, $perPage: Int!) {
      Page(page: $page, perPage: $perPage) {
        media(type: ANIME, sort: TRENDING_DESC, isAdult: false) {
          id
          title {
            romaji
            english
            native
          }
          description(asHtml: false)
          episodes
          seasonYear
          averageScore
          coverImage {
            large
          }
          genres
          format
          status
        }
      }
    }
    """
}

private struct AniListGraphQLRequest: Encodable {
    let query: String
    let variables: AniListVariables
}

private struct AniListVariables: Encodable {
    let page: Int
    let perPage: Int
    let search: String?

    init(page: Int, perPage: Int, search: String? = nil) {
        self.page = page
        self.perPage = perPage
        self.search = search
    }
}

private struct AniListEnvelope: Decodable {
    let data: AniListData?
    let errors: [AniListGraphQLError]?
}

private struct AniListData: Decodable {
    let page: AniListPage?

    enum CodingKeys: String, CodingKey {
        case page = "Page"
    }
}

private struct AniListPage: Decodable {
    let media: [AniListMedia]?
}

private struct AniListMedia: Decodable {
    let id: Int
    let title: AniListTitle?
    let description: String?
    let episodes: Int?
    let seasonYear: Int?
    let averageScore: Int?
    let coverImage: AniListCoverImage?
    let genres: [String]?
    let format: String?
    let status: String?
}

private struct AniListTitle: Decodable {
    let romaji: String?
    let english: String?
    let native: String?
}

private struct AniListCoverImage: Decodable {
    let large: String?
}

private struct AniListGraphQLError: Decodable {
    let message: String
}

enum AniListCatalogError: LocalizedError {
    case emptyQuery
    case invalidPagination
    case invalidResponse
    case invalidData
    case rateLimited
    case server(Int)
    case network(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter an anime title to search AniList."
        case .invalidPagination:
            return "Choose a page above zero and between 1 and 50 anime per page."
        case .invalidResponse:
            return "AniList returned an invalid network response."
        case .invalidData:
            return "AniList returned data CineNex could not understand."
        case .rateLimited:
            return "AniList rate limit reached. Wait a moment and try again."
        case .server(let status):
            return "AniList returned HTTP \(status). Try again later."
        case .network(let message):
            return "Could not reach AniList: \(message)"
        case .api(let message):
            return "AniList could not complete the request: \(message)"
        }
    }
}
