import Combine
import Foundation

enum GenreCatalogOrder: String, Sendable {
    case popular, newest, rating
    var tmdbSort: String {
        switch self { case .popular: return "popularity.desc"; case .newest: return "primary_release_date.desc"; case .rating: return "vote_average.desc" }
    }
}

struct GenreCatalogQuery: Equatable, Sendable {
    let genre: String?
    let kind: MediaKind?
    let order: GenreCatalogOrder
    init(genre: String? = nil, kind: MediaKind? = nil, order: GenreCatalogOrder = .popular) {
        let clean = genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.genre = clean.isEmpty ? nil : clean
        self.kind = kind
        self.order = order
    }
    var kinds: [MediaKind] { kind.map { [$0] } ?? [.movie, .series] }

    func matches(_ item: MediaItem, allowingUnreportedGenre: Bool = false) -> Bool {
        guard kind == nil || kind == item.kind else { return false }
        guard let genre else { return true }
        let requested = GenreCatalogGenres.normalized(genre)
        let tokens = item.genre.components(separatedBy: CharacterSet(charactersIn: "·,|/"))
            .map(GenreCatalogGenres.normalized).filter { !["", "movie", "series", "tv"].contains($0) }
        guard !tokens.isEmpty else { return allowingUnreportedGenre }
        return tokens.contains { GenreCatalogGenres.matches(requested: requested, candidate: $0) }
    }
}

enum GenreCatalogError: LocalizedError, Equatable {
    case unsupportedGenre(String), invalidPage, invalidResponse, network(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedGenre(let genre): return "The connected catalog does not provide a separate \(genre) collection. Cached matching titles remain available."
        case .invalidPage: return "The catalog returned an unexpected page. Refresh this collection to continue."
        case .invalidResponse: return "The collection provider returned an invalid response."
        case .network(let detail): return "The collection could not load. \(detail)"
        }
    }
}

/// Canonical mappings keep movie and TV taxonomies distinct. Unknown labels never become an unfiltered request.
enum GenreCatalogGenres {
    static func normalized(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "science fiction", with: "sci-fi")
            .replacingOccurrences(of: "sci fi", with: "sci-fi")
        switch value {
        case "action and adventure": return "action & adventure"
        case "sci-fi and fantasy": return "sci-fi & fantasy"
        case "war and politics": return "war & politics"
        case "reality-tv": return "reality"
        case "talk-show": return "talk"
        default: return value
        }
    }
    static func matches(requested: String, candidate: String) -> Bool {
        if requested == candidate { return true }
        let combined: [String: Set<String>] = ["action & adventure": ["action", "adventure"],
                                               "sci-fi & fantasy": ["sci-fi", "fantasy"],
                                               "war & politics": ["war", "politics"]]
        if combined[requested]?.contains(candidate) == true { return true }
        return combined[candidate]?.contains(requested) == true
    }
    static func tmdbIDs(_ genre: String?, kind: MediaKind) -> [Int]? {
        guard let genre else { return [] }
        let movie: [String: [Int]] = ["action": [28], "adventure": [12], "action & adventure": [28, 12],
            "animation": [16], "comedy": [35], "crime": [80], "documentary": [99], "drama": [18],
            "family": [10751], "fantasy": [14], "history": [36], "horror": [27], "music": [10402],
            "mystery": [9648], "romance": [10749], "sci-fi": [878], "sci-fi & fantasy": [878, 14],
            "tv movie": [10770], "thriller": [53], "war": [10752], "war & politics": [10752], "western": [37]]
        let series: [String: [Int]] = ["action": [10759], "adventure": [10759], "action & adventure": [10759],
            "animation": [16], "comedy": [35], "crime": [80], "documentary": [99], "drama": [18],
            "family": [10751], "kids": [10762], "mystery": [9648], "news": [10763], "reality": [10764],
            "sci-fi": [10765], "fantasy": [10765], "sci-fi & fantasy": [10765], "soap": [10766],
            "talk": [10767], "war": [10768], "politics": [10768], "war & politics": [10768], "western": [37]]
        return (kind == .movie ? movie : series)[normalized(genre)]
    }
    static func cinemetaGenres(_ genre: String?, kind: MediaKind) -> [String?]? {
        guard let genre else { return [nil] }
        let common: [String: [String?]] = ["action": ["Action"], "adventure": ["Adventure"],
            "action & adventure": ["Action", "Adventure"], "animation": ["Animation"], "biography": ["Biography"],
            "comedy": ["Comedy"], "crime": ["Crime"], "documentary": ["Documentary"], "drama": ["Drama"],
            "family": ["Family"], "fantasy": ["Fantasy"], "history": ["History"], "horror": ["Horror"],
            "mystery": ["Mystery"], "romance": ["Romance"], "sci-fi": ["Sci-Fi"],
            "sci-fi & fantasy": ["Sci-Fi", "Fantasy"], "sport": ["Sport"], "thriller": ["Thriller"],
            "war": ["War"], "western": ["Western"]]
        let key = normalized(genre)
        if let value = common[key] { return value }
        if kind == .series {
            let television: [String: [String?]] = ["reality": ["Reality-TV"], "talk": ["Talk-Show"], "game-show": ["Game-Show"]]
            return television[key]
        }
        return nil
    }
}

struct GenreCatalogCursor: Equatable, Sendable {
    let positions: [String: Int]
}
struct GenreCatalogPage: Sendable {
    let items: [MediaItem]
    let next: GenreCatalogCursor?
}
protocol GenreCatalogPaging: Sendable {
    func page(query: GenreCatalogQuery, cursor: GenreCatalogCursor?) async throws -> GenreCatalogPage
}

struct GenreCatalogProvider: GenreCatalogPaging {
    private let token: String
    private let session: URLSession
    init(readAccessToken: String = "", session: URLSession? = nil) {
        token = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }
    private struct Branch: Sendable {
        let key: String
        let kind: MediaKind
        let genre: String?
        let genreIDs: [Int]
        let position: Int
        let usesTMDB: Bool
    }
    private struct Result: Sendable {
        let key: String
        let items: [MediaItem]
        let nextPosition: Int?
    }

    func page(query: GenreCatalogQuery, cursor: GenreCatalogCursor?) async throws -> GenreCatalogPage {
        var branches: [Branch] = []
        for kind in query.kinds {
            if !token.isEmpty, let ids = GenreCatalogGenres.tmdbIDs(query.genre, kind: kind) {
                let key = "tmdb-\(kind.rawValue)"
                let position = cursor == nil ? 1 : cursor?.positions[key]
                if let position { branches.append(Branch(key: key, kind: kind, genre: query.genre, genreIDs: ids, position: position, usesTMDB: true)) }
            } else {
                guard let genres = GenreCatalogGenres.cinemetaGenres(query.genre, kind: kind) else { continue }
                for genre in genres {
                    let key = "cinemeta-\(kind.rawValue)-\(genre ?? "all")"
                    let position = cursor == nil ? 0 : cursor?.positions[key]
                    if let position { branches.append(Branch(key: key, kind: kind, genre: genre, genreIDs: [], position: position, usesTMDB: false)) }
                }
            }
        }
        guard !branches.isEmpty else { throw GenreCatalogError.unsupportedGenre(query.genre ?? "requested") }
        return try await withThrowingTaskGroup(of: Result.self) { group in
            for branch in branches {
                group.addTask {
                    if branch.usesTMDB { return try await tmdbPage(branch, order: query.order) }
                    let page = try await CinemetaCatalogProvider(session: session)
                        .catalogPage(type: branch.kind == .movie ? "movie" : "series", genre: branch.genre, skip: branch.position)
                    return Result(key: branch.key, items: page.items, nextPosition: page.hasMore ? branch.position + 100 : nil)
                }
            }
            var results: [String: Result] = [:]
            for try await result in group { results[result.key] = result }
            var items: [MediaItem] = [], next: [String: Int] = [:]
            for branch in branches {
                guard let result = results[branch.key] else { throw GenreCatalogError.invalidResponse }
                items.append(contentsOf: result.items.filter { query.matches($0, allowingUnreportedGenre: true) })
                next[result.key] = result.nextPosition
            }
            var seen = Set<String>()
            return GenreCatalogPage(items: items.filter { seen.insert($0.id).inserted },
                                    next: next.isEmpty ? nil : GenreCatalogCursor(positions: next))
        }
    }

    private func tmdbPage(_ branch: Branch, order: GenreCatalogOrder) async throws -> Result {
        guard (1...500).contains(branch.position) else { throw GenreCatalogError.invalidPage }
        var components = URLComponents(string: "https://api.themoviedb.org/3/discover/\(branch.kind == .movie ? "movie" : "tv")")!
        components.queryItems = [URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "include_adult", value: "false"), URLQueryItem(name: "sort_by", value: order == .newest && branch.kind == .series ? "first_air_date.desc" : order.tmdbSort),
            URLQueryItem(name: "page", value: String(branch.position))]
        if !branch.genreIDs.isEmpty { components.queryItems?.append(URLQueryItem(name: "with_genres", value: branch.genreIDs.map(String.init).joined(separator: "|"))) }
        if order == .rating { components.queryItems?.append(URLQueryItem(name: "vote_count.gte", value: "100")) }
        if order == .newest { components.queryItems?.append(URLQueryItem(name: branch.kind == .movie ? "primary_release_date.lte" : "first_air_date.lte", value: EpisodeNavigatorPolicy.utcToday())) }
        guard let url = components.url else { throw GenreCatalogError.invalidPage }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request, delegate: AccountNoRedirectDelegate())
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else { throw GenreCatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw TMDBCatalogError.unauthorized }
            if http.statusCode == 429 { throw TMDBCatalogError.rateLimited }
            throw TMDBCatalogError.server(http.statusCode)
        }
        let page = try TMDBCatalogProvider.mapDiscoveryPage(data, mediaType: branch.kind == .movie ? "movie" : "tv", requestedPage: branch.position)
        guard page.page == branch.position else { throw GenreCatalogError.invalidPage }
        return Result(key: branch.key, items: page.items, nextPosition: page.page < min(500, page.totalPages) ? page.page + 1 : nil)
    }
}

/// Resolve secure credentials off the UI actor only when the collection actually loads.
actor DeferredGenreCatalogProvider: GenreCatalogPaging {
    private var provider: GenreCatalogProvider?
    func page(query: GenreCatalogQuery, cursor: GenreCatalogCursor?) async throws -> GenreCatalogPage {
        if provider == nil {
            let settings = try? await SourceSecureSettingsLoader.shared.load()
            try Task.checkCancellation()
            provider = GenreCatalogProvider(readAccessToken: settings?.tmdbToken ?? "")
        }
        guard let provider else { throw GenreCatalogError.invalidResponse }
        return try await provider.page(query: query, cursor: cursor)
    }
}

@MainActor
final class GenreCatalogModel: ObservableObject {
    @Published private(set) var items: [MediaItem]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true
    @Published private(set) var autoFillPaused = false
    @Published private(set) var pagesLoaded = 0
    private(set) var query: GenreCatalogQuery
    private let seedItems: [MediaItem]
    private let provider: any GenreCatalogPaging
    private var cursor: GenreCatalogCursor?
    private var generation = UUID()
    private var hasLoaded = false

    init(query: GenreCatalogQuery, seedItems: [MediaItem], provider: any GenreCatalogPaging) {
        self.query = query
        self.seedItems = seedItems
        self.provider = provider
        var seen = Set<String>()
        items = seedItems.filter { query.matches($0) && seen.insert($0.id).inserted }
    }

    func ensureLoaded(query: GenreCatalogQuery) async {
        if query != self.query || !hasLoaded { await reload(query: query) }
    }

    func reload(query: GenreCatalogQuery? = nil) async {
        generation = UUID()
        if let query { self.query = query }
        cursor = nil
        hasLoaded = false
        hasMore = true
        pagesLoaded = 0
        autoFillPaused = false
        isLoading = false
        errorMessage = nil
        var seen = Set<String>()
        items = seedItems.filter { self.query.matches($0) && seen.insert($0.id).inserted }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore, !Task.isCancelled else { return }
        let requestGeneration = generation
        let requestQuery = query
        isLoading = true
        errorMessage = nil
        autoFillPaused = false
        defer { if generation == requestGeneration { isLoading = false } }
        var newItems: [MediaItem] = []
        var seen = Set(items.map(\.id))
        do {
            // Fill short/duplicate pages without waiting for the same footer to reappear. A batch
            // stops after three responses without enough additions, preventing an unbounded scan.
            for _ in 0..<3 {
                let page = try await provider.page(query: requestQuery, cursor: hasLoaded ? cursor : nil)
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                hasLoaded = true
                cursor = page.next
                hasMore = page.next != nil
                pagesLoaded += 1
                let additions = page.items.filter { seen.insert($0.id).inserted }
                newItems.append(contentsOf: additions)
                items.append(contentsOf: additions)
                if !hasMore || newItems.count >= 20 { break }
            }
            guard generation == requestGeneration else { return }
            autoFillPaused = hasMore && newItems.isEmpty
        } catch is CancellationError { return }
        catch {
            guard generation == requestGeneration else { return }
            // Successfully completed responses were already appended; a retry starts at the failed cursor.
            errorMessage = error.localizedDescription
        }
    }

    func invalidate() { generation = UUID(); isLoading = false }
}
