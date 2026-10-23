import Combine
import Foundation

struct TraktHistoryMovie: Decodable, Identifiable, Hashable {
    struct Movie: Decodable, Hashable {
        struct Identifiers: Decodable, Hashable {
            let tmdb: Int?
        }

        let title: String
        let year: Int?
        let ids: Identifiers?
    }

    let watchedAt: String?
    let plays: Int?
    let movie: Movie

    enum CodingKeys: String, CodingKey {
        case watchedAt = "watched_at"
        case plays
        case movie
    }

    var title: String { movie.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var year: Int? { movie.year }
    var tmdbID: Int? { movie.ids?.tmdb }
    var playCount: Int { max(1, plays ?? 1) }

    var id: String {
        if let tmdbID, tmdbID > 0 {
            return "tmdb-movie-\(tmdbID)"
        }
        return "title-\(title.lowercased())-\(year ?? 0)"
    }

    static func decodeList(_ data: Data) throws -> [TraktHistoryMovie] {
        let decoded = try JSONDecoder().decode([TraktHistoryMovie].self, from: data)
        var byID: [String: TraktHistoryMovie] = [:]
        for entry in decoded where !entry.title.isEmpty {
            if let existing = byID[entry.id] {
                let currentDate = existing.watchedAt ?? ""
                let candidateDate = entry.watchedAt ?? ""
                let latest = candidateDate > currentDate ? entry : existing
                byID[entry.id] = TraktHistoryMovie(
                    watchedAt: latest.watchedAt,
                    plays: max(existing.playCount, entry.playCount),
                    movie: latest.movie
                )
            } else {
                byID[entry.id] = entry
            }
        }
        return byID.values.sorted {
            ($0.watchedAt ?? "") > ($1.watchedAt ?? "")
        }
    }
}

struct TraktHistoryEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let tmdbID: Int?
    let watchedAt: String?
    let plays: Int

    init(
        id: String,
        title: String,
        year: Int?,
        tmdbID: Int?,
        watchedAt: String?,
        plays: Int
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.tmdbID = tmdbID
        self.watchedAt = watchedAt
        self.plays = plays
    }

    init(movie: TraktHistoryMovie) {
        id = movie.id
        title = movie.title
        year = movie.year
        tmdbID = movie.tmdbID
        watchedAt = movie.watchedAt
        plays = movie.playCount
    }
}

@MainActor
final class TraktHistoryStore: ObservableObject {
    static let shared = TraktHistoryStore()

    @Published private(set) var entries: [TraktHistoryEntry]

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.trakt.history") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([TraktHistoryEntry].self, from: data) {
            var seen = Set<String>()
            entries = saved.filter { seen.insert($0.id).inserted && !$0.title.isEmpty }
                .sorted { ($0.watchedAt ?? "") > ($1.watchedAt ?? "") }
        } else {
            entries = []
        }
    }

    @discardableResult
    func importMovies(_ movies: [TraktHistoryMovie]) -> Int {
        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let originalCount = merged.count
        for movie in movies where !movie.title.isEmpty {
            let incoming = TraktHistoryEntry(movie: movie)
            if let existing = merged[incoming.id] {
                let existingDate = existing.watchedAt ?? ""
                let incomingDate = incoming.watchedAt ?? ""
                merged[incoming.id] = TraktHistoryEntry(
                    id: incoming.id,
                    title: incomingDate >= existingDate ? incoming.title : existing.title,
                    year: incoming.year ?? existing.year,
                    tmdbID: incoming.tmdbID ?? existing.tmdbID,
                    watchedAt: max(existingDate, incomingDate).isEmpty ? nil : max(existingDate, incomingDate),
                    plays: max(existing.plays, incoming.plays)
                )
            } else {
                merged[incoming.id] = incoming
            }
        }
        entries = merged.values.sorted {
            let leftDate = $0.watchedAt ?? ""
            let rightDate = $1.watchedAt ?? ""
            if leftDate != rightDate { return leftDate > rightDate }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
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
