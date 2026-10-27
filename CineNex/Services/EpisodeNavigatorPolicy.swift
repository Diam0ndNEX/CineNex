import Combine
import Foundation

/// Original Swift implementation of navigation behavior referenced from Nuvio's DetailEpisodeNavigator.
enum EpisodeNavigatorSort: String, CaseIterable, Identifiable {
    case firstToLast, lastToFirst, newestAired, highestRated, unwatchedFirst
    var id: String { rawValue }
    var title: String {
        switch self {
        case .firstToLast: return "First to last"
        case .lastToFirst: return "Last to first"
        case .newestAired: return "Newest aired"
        case .highestRated: return "Highest rated"
        case .unwatchedFirst: return "Unwatched first"
        }
    }
}

enum EpisodeNavigatorFilter: String, CaseIterable, Identifiable {
    case all, unwatched, watched
    var id: String { rawValue }
    var title: String { self == .all ? "All episodes" : rawValue.capitalized }
}

struct EpisodeNavigatorIdentity: Codable, Hashable, Sendable {
    let itemID: String
    let season: Int
    let episode: Int
    var isValid: Bool { !itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && season >= 0 && episode > 0 }
}

enum EpisodeNavigatorPolicy {
    static func filtered(_ episodes: [TMDBSeasonEpisode], query: String, sort: EpisodeNavigatorSort,
                         filter: EpisodeNavigatorFilter = .all, watched: Set<Int> = [], today: String = utcToday()) -> [TMDBSeasonEpisode] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return episodes.filter { episode in
            let matchesStatus = filter == .all || (filter == .watched ? watched.contains(episode.episodeNumber) : !watched.contains(episode.episodeNumber))
            let matchesQuery = query.isEmpty || Int(query) == episode.episodeNumber
                || episode.displayName.localizedCaseInsensitiveContains(query)
                || (episode.overview?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesStatus && matchesQuery
        }.sorted { lhs, rhs in
            switch sort {
            case .firstToLast: break
            case .lastToFirst:
                if lhs.episodeNumber != rhs.episodeNumber { return lhs.episodeNumber > rhs.episodeNumber }
            case .newestAired:
                let leftDate = airedDate(lhs.airDate, today: today) ?? ""
                let rightDate = airedDate(rhs.airDate, today: today) ?? ""
                if leftDate != rightDate { return leftDate > rightDate }
            case .highestRated:
                let left = validRating(lhs.voteAverage) ?? -1
                let right = validRating(rhs.voteAverage) ?? -1
                if left != right { return left > right }
            case .unwatchedFirst:
                let left = watched.contains(lhs.episodeNumber), right = watched.contains(rhs.episodeNumber)
                if left != right { return !left }
            }
            if lhs.episodeNumber != rhs.episodeNumber { return lhs.episodeNumber < rhs.episodeNumber }
            return lhs.id < rhs.id
        }
    }

    static func nextUnwatched(_ episodes: [TMDBSeasonEpisode], watched: Set<Int>, today: String = utcToday()) -> TMDBSeasonEpisode? {
        episodes.filter { episode in
            guard !watched.contains(episode.episodeNumber) else { return false }
            // Unknown dates remain discoverable; a known future date never becomes “up next”.
            guard let date = validDate(episode.airDate) else { return true }
            return date <= today
        }.min { lhs, rhs in lhs.episodeNumber == rhs.episodeNumber ? lhs.id < rhs.id : lhs.episodeNumber < rhs.episodeNumber }
    }

    static func validRating(_ rating: Double?) -> Double? {
        guard let rating, rating.isFinite, rating > 0, rating <= 10 else { return nil }
        return rating
    }
    static func validDate(_ date: String?) -> String? {
        guard let date, date.utf8.count == 10 else { return nil }
        let components = date.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3, components[0].count == 4, components[1].count == 2, components[2].count == 2,
              components.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(components[0]), year > 0, let month = Int(components[1]), (1...12).contains(month),
              let day = Int(components[2]) else { return nil }
        let leap = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { return nil }
        return date
    }
    static func utcToday(_ now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
    private static func airedDate(_ date: String?, today: String) -> String? {
        guard let date = validDate(date), date <= today else { return nil }
        return date
    }
}

/// Manual local marks are intentionally distinct from movie resume progress and connected account lists.
@MainActor
final class EpisodeNavigatorHistory: ObservableObject {
    static let shared = EpisodeNavigatorHistory()
    @Published private(set) var watched: Set<EpisodeNavigatorIdentity>
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "cinenex.episodeNavigator.watched.v1") {
        self.defaults = defaults
        self.key = key
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Set<EpisodeNavigatorIdentity>.self, from: $0) } ?? []
        watched = Set(decoded.filter(\.isValid))
    }
    func numbers(itemID: String, season: Int) -> Set<Int> {
        Set(watched.filter { $0.itemID == itemID && $0.season == season }.map(\.episode))
    }
    func setWatched(_ value: Bool, itemID: String, season: Int, episode: Int) {
        let identity = EpisodeNavigatorIdentity(itemID: itemID, season: season, episode: episode)
        guard identity.isValid else { return }
        if value { watched.insert(identity) } else { watched.remove(identity) }
        if let data = try? JSONEncoder().encode(watched) { defaults.set(data, forKey: key) }
    }
}
