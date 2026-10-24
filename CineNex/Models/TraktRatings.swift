import Combine
import Foundation

struct TraktRatingMovie: Decodable, Identifiable, Hashable {
    struct Movie: Decodable, Hashable {
        struct Identifiers: Decodable, Hashable {
            let tmdb: Int?
        }

        let title: String
        let year: Int?
        let ids: Identifiers?
    }

    let ratedAt: String?
    let rating: Int
    let movie: Movie

    enum CodingKeys: String, CodingKey {
        case ratedAt = "rated_at"
        case rating
        case movie
    }

    var title: String { movie.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var year: Int? { movie.year }
    var tmdbID: Int? { movie.ids?.tmdb }

    var ratingLabel: String? {
        guard (1...10).contains(rating) else { return nil }
        return "\(rating) / 10"
    }

    var id: String {
        if let tmdbID, tmdbID > 0 {
            return "tmdb-movie-\(tmdbID)"
        }
        return "title-\(title.lowercased())-\(year ?? 0)"
    }

    static func decodeList(_ data: Data) throws -> [TraktRatingMovie] {
        let decoded = try JSONDecoder().decode([TraktRatingMovie].self, from: data)
        var byID: [String: TraktRatingMovie] = [:]
        for entry in decoded where !entry.title.isEmpty && (1...10).contains(entry.rating) {
            if let existing = byID[entry.id] {
                let existingDate = existing.ratedAt ?? ""
                let candidateDate = entry.ratedAt ?? ""
                if candidateDate > existingDate {
                    byID[entry.id] = entry
                }
            } else {
                byID[entry.id] = entry
            }
        }
        return byID.values.sorted {
            let leftDate = $0.ratedAt ?? ""
            let rightDate = $1.ratedAt ?? ""
            if leftDate != rightDate { return leftDate > rightDate }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

struct TraktRatingEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let tmdbID: Int?
    let ratedAt: String?
    let rating: Int

    init(
        id: String,
        title: String,
        year: Int?,
        tmdbID: Int?,
        ratedAt: String?,
        rating: Int
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.tmdbID = tmdbID
        self.ratedAt = ratedAt
        self.rating = rating
    }

    init(movie: TraktRatingMovie) {
        self.init(
            id: movie.id,
            title: movie.title,
            year: movie.year,
            tmdbID: movie.tmdbID,
            ratedAt: movie.ratedAt,
            rating: movie.rating
        )
    }
}

@MainActor
final class TraktRatingStore: ObservableObject {
    static let shared = TraktRatingStore()

    @Published private(set) var entries: [TraktRatingEntry]

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.trakt.ratings") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([TraktRatingEntry].self, from: data) {
            var entriesByID: [String: TraktRatingEntry] = [:]
            for entry in saved {
                let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !title.isEmpty, (1...10).contains(entry.rating) else { continue }

                let normalized = TraktRatingEntry(
                    id: id,
                    title: title,
                    year: entry.year,
                    tmdbID: entry.tmdbID,
                    ratedAt: entry.ratedAt,
                    rating: entry.rating
                )
                if let existing = entriesByID[id] {
                    if (normalized.ratedAt ?? "") > (existing.ratedAt ?? "") {
                        entriesByID[id] = normalized
                    }
                } else {
                    entriesByID[id] = normalized
                }
            }
            entries = entriesByID.values.sorted {
                let leftDate = $0.ratedAt ?? ""
                let rightDate = $1.ratedAt ?? ""
                if leftDate != rightDate { return leftDate > rightDate }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        } else {
            entries = []
        }
    }

    @discardableResult
    func importMovies(_ movies: [TraktRatingMovie]) -> Int {
        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let originalCount = merged.count
        for movie in movies where !movie.title.isEmpty && (1...10).contains(movie.rating) {
            let incoming = TraktRatingEntry(movie: movie)
            if let existing = merged[incoming.id] {
                let existingDate = existing.ratedAt ?? ""
                let incomingDate = incoming.ratedAt ?? ""
                if incomingDate >= existingDate {
                    merged[incoming.id] = incoming
                }
            } else {
                merged[incoming.id] = incoming
            }
        }
        entries = merged.values.sorted {
            let leftDate = $0.ratedAt ?? ""
            let rightDate = $1.ratedAt ?? ""
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
