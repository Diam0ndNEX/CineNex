import Foundation

struct TraktWatchlistMovie: Decodable, Identifiable, Hashable {
    struct Movie: Decodable, Hashable {
        struct Identifiers: Decodable, Hashable {
            let tmdb: Int?
        }

        let title: String
        let year: Int?
        let ids: Identifiers?
    }

    let movie: Movie
    let listedAt: String?

    enum CodingKeys: String, CodingKey {
        case movie
        case listedAt = "listed_at"
    }

    var id: String {
        if let tmdbID, tmdbID > 0 {
            return "tmdb-movie-\(tmdbID)"
        }
        return "title-\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())-\(year ?? 0)"
    }

    var title: String { movie.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var year: Int? { movie.year }
    var tmdbID: Int? { movie.ids?.tmdb }

    static func decodeList(_ data: Data) throws -> [TraktWatchlistMovie] {
        let decoded = try JSONDecoder().decode([TraktWatchlistMovie].self, from: data)
        var seen = Set<String>()
        return decoded.filter { entry in
            guard !entry.title.isEmpty else { return false }
            return seen.insert(entry.id).inserted
        }
    }
}

struct TraktWatchlistEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let tmdbID: Int?
    let addedAt: String?

    init(movie: TraktWatchlistMovie) {
        id = movie.id
        title = movie.title
        year = movie.year
        tmdbID = movie.tmdbID
        addedAt = movie.listedAt
    }
}

@MainActor
final class TraktWatchlistStore: ObservableObject {
    static let shared = TraktWatchlistStore()

    @Published private(set) var entries: [TraktWatchlistEntry]

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.trakt.watchlist") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([TraktWatchlistEntry].self, from: data) {
            var seen = Set<String>()
            entries = saved.filter { seen.insert($0.id).inserted && !$0.title.isEmpty }
        } else {
            entries = []
        }
    }

    @discardableResult
    func importMovies(_ movies: [TraktWatchlistMovie]) -> Int {
        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let originalCount = merged.count
        for movie in movies where !movie.title.isEmpty {
            merged[movie.id] = TraktWatchlistEntry(movie: movie)
        }
        entries = merged.values.sorted {
            let left = $0.title.localizedStandardCompare($1.title)
            if left == .orderedSame {
                return ($0.year ?? 0) < ($1.year ?? 0)
            }
            return left == .orderedAscending
        }
        persist()
        return entries.count - originalCount
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

