import Foundation

struct TMDBCatalogProvider: CatalogProvider {
    let providerName = "TMDB Trending"
    private let readAccessToken: String
    private let session: URLSession

    init(readAccessToken: String, session: URLSession = .shared) {
        self.readAccessToken = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func fetchCatalog() async throws -> [MediaItem] {
        let url = URL(string: "https://api.themoviedb.org/3/trending/all/week?language=en-US")!
        return try Self.mapResponse(await fetchData(from: url))
    }

    func search(query: String) async throws -> [MediaItem] {
        let page = try await searchPage(query: query, page: 1)
        return page.items
    }

    func searchPage(query: String, page: Int) async throws -> TMDBSearchPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return TMDBSearchPage(items: [], page: 1, totalPages: 1) }
        guard page > 0 else { throw TMDBCatalogError.invalidURL }
        var components = URLComponents(string: "https://api.themoviedb.org/3/search/multi")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "page", value: String(page))
        ]
        guard let url = components?.url else { throw TMDBCatalogError.invalidURL }
        let data = try await fetchData(from: url)
        return try Self.mapSearchPage(data, requestedPage: page)
    }

    static func mapSearchPage(_ data: Data, requestedPage: Int) throws -> TMDBSearchPage {
        guard requestedPage > 0 else { throw TMDBCatalogError.invalidURL }
        let items = try mapResponse(data)
        let response: SearchPaginationResponse
        do {
            response = try JSONDecoder().decode(SearchPaginationResponse.self, from: data)
        } catch {
            throw TMDBCatalogError.invalidData
        }
        let totalPages = max(1, response.totalPages ?? requestedPage)
        return TMDBSearchPage(
            items: items,
            page: min(totalPages, max(1, response.page ?? requestedPage)),
            totalPages: totalPages
        )
    }

    func fetchDetails(for item: MediaItem) async throws -> TMDBTitleDetails? {
        guard item.metadataProvider == "tmdb", let id = item.externalID, id > 0 else {
            return nil
        }
        let mediaType = item.kind == .movie ? "movie" : "tv"
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(mediaType)/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "append_to_response", value: "credits,videos,recommendations")
        ]
        guard let url = components?.url else { throw TMDBCatalogError.invalidURL }
        let data = try await fetchData(from: url)
        do {
            return try JSONDecoder().decode(TMDBTitleDetails.self, from: data)
        } catch {
            throw TMDBCatalogError.invalidData
        }
    }


    func fetchSeasonEpisodes(for item: MediaItem, seasonNumber: Int) async throws -> [TMDBSeasonEpisode] {
        guard item.kind == .series,
              item.metadataProvider == "tmdb",
              let id = item.externalID,
              id > 0,
              seasonNumber >= 0 else {
            throw TMDBCatalogError.invalidURL
        }
        var components = URLComponents(string: "https://api.themoviedb.org/3/tv/\(id)/season/\(seasonNumber)")
        components?.queryItems = [URLQueryItem(name: "language", value: "en-US")]
        guard let url = components?.url else { throw TMDBCatalogError.invalidURL }
        let data = try await fetchData(from: url)
        do {
            return try JSONDecoder().decode(TMDBSeasonDetails.self, from: data).episodeList
        } catch {
            throw TMDBCatalogError.invalidData
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        guard !readAccessToken.isEmpty else { throw TMDBCatalogError.missingToken }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(readAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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
        return data
    }

    static func mapResponse(_ data: Data) throws -> [MediaItem] {
        let decoded: TrendingResponse
        do {
            decoded = try JSONDecoder().decode(TrendingResponse.self, from: data)
        } catch {
            throw TMDBCatalogError.invalidData
        }

        var seenIDs = Set<String>()
        return decoded.results.compactMap { result in
            guard result.mediaType == "movie" || result.mediaType == "tv" else { return nil }
            let stableID = "tmdb-\(result.mediaType)-\(result.id)"
            guard seenIDs.insert(stableID).inserted else { return nil }
            let isMovie = result.mediaType == "movie"
            let title = (isMovie ? result.title : result.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { return nil }
            let date = isMovie ? result.releaseDate : result.firstAirDate
            let year = date.flatMap { Int($0.prefix(4)) } ?? 0
            let overview = result.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
            let synopsis = (overview?.isEmpty == false ? overview! : "No description is available from TMDB yet.")
            let posterURL = result.posterPath.flatMap {
                URL(string: "https://image.tmdb.org/t/p/w500\($0)")
            }
            return MediaItem(
                id: stableID,
                title: title,
                kind: isMovie ? .movie : .series,
                year: year,
                genre: genreNames(for: result.genreIDs ?? [], isMovie: isMovie),
                synopsis: synopsis,
                symbol: isMovie ? "film" : "tv",
                runtime: isMovie ? "Movie" : "Series",
                streamURL: nil,
                posterURL: posterURL,
                rating: result.voteAverage,
                externalID: result.id,
                metadataProvider: "tmdb"
            )
        }
    }

    private static func genreNames(for ids: [Int], isMovie: Bool) -> String {
        let genres: [Int: String] = isMovie
            ? [
                28: "Action",
                12: "Adventure",
                16: "Animation",
                35: "Comedy",
                80: "Crime",
                99: "Documentary",
                18: "Drama",
                10751: "Family",
                14: "Fantasy",
                36: "History",
                27: "Horror",
                10402: "Music",
                9648: "Mystery",
                10749: "Romance",
                878: "Sci-Fi",
                10770: "TV Movie",
                53: "Thriller",
                10752: "War",
                37: "Western"
            ]
            : [
                10759: "Action & Adventure",
                16: "Animation",
                35: "Comedy",
                80: "Crime",
                99: "Documentary",
                18: "Drama",
                10751: "Family",
                10762: "Kids",
                9648: "Mystery",
                10763: "News",
                10764: "Reality",
                10765: "Sci-Fi & Fantasy",
                10766: "Soap",
                10767: "Talk",
                10768: "War & Politics",
                37: "Western"
            ]

        var seenNames = Set<String>()
        let mapped = ids.compactMap { id -> String? in
            guard let name = genres[id], seenNames.insert(name).inserted else { return nil }
            return name
        }
        return mapped.isEmpty ? (isMovie ? "Movie" : "Series") : mapped.joined(separator: " · ")
    }
}

struct TMDBSearchPage: Equatable {
    let items: [MediaItem]
    let page: Int
    let totalPages: Int

    var hasMorePages: Bool { page < totalPages }
}

private struct SearchPaginationResponse: Decodable {
    let page: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case totalPages = "total_pages"
    }
}

private struct TrendingResponse: Decodable {
    let results: [TrendingResult]
}

private struct TrendingResult: Decodable {
    let id: Int
    let mediaType: String
    let title: String?
    let name: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let genreIDs: [Int]?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }
}

enum TMDBCatalogError: LocalizedError {
    case missingToken
    case invalidURL
    case invalidResponse
    case invalidData
    case unauthorized
    case rateLimited
    case server(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add your TMDB Read Access Token in Tracking to load live catalog metadata."
        case .invalidURL:
            return "CineNex could not create the TMDB request URL."
        case .invalidResponse:
            return "TMDB returned an invalid network response."
        case .invalidData:
            return "TMDB returned data CineNex could not understand."
        case .unauthorized:
            return "TMDB rejected the token. Check that you copied the Read Access Token correctly."
        case .rateLimited:
            return "TMDB rate limit reached. Wait a moment and refresh again."
        case .server(let status):
            return "TMDB returned HTTP \(status). Try again later."
        case .network(let message):
            return "Could not reach TMDB: \(message)"
        }
    }
}
