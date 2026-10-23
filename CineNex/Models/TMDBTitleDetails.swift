import Foundation

struct TMDBTitleDetails: Decodable, Equatable {
    let tagline: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let status: String?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let genres: [TMDBTitleGenre]?

    enum CodingKeys: String, CodingKey {
        case tagline
        case runtime
        case status
        case genres
        case episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
    }

    var runtimeMinutes: Int? {
        if let runtime, runtime > 0 {
            return runtime
        }
        guard let episodeRuntime = episodeRunTime?.first, episodeRuntime > 0 else {
            return nil
        }
        return episodeRuntime
    }

    var runtimeLabel: String? {
        guard let minutes = runtimeMinutes else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 {
            return "\(hours) hr \(remainder) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(remainder) min"
    }

    var genreNames: [String] {
        (genres ?? []).compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct TMDBTitleGenre: Decodable, Equatable {
    let name: String?
}
