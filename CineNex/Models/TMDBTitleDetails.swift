import Foundation

struct TMDBTitleDetails: Decodable, Equatable {
    let tagline: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let status: String?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let genres: [TMDBTitleGenre]?
    let credits: TMDBTitleCredits?
    let videos: TMDBTitleVideos?
    let createdBy: [TMDBTitleCreator]?

    enum CodingKeys: String, CodingKey {
        case tagline
        case runtime
        case status
        case genres
        case credits
        case videos
        case createdBy = "created_by"
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

    var castMembers: [TMDBTitleCastMember] {
        (credits?.cast ?? []).filter {
            !($0.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.prefix(12).map { $0 }
    }

    var directorNames: [String] {
        (credits?.crew ?? []).filter { $0.job?.caseInsensitiveCompare("Director") == .orderedSame }
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    var creatorNames: [String] {
        (createdBy ?? []).compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    var trailerURL: URL? {
        let candidates = (videos?.results ?? []).filter {
            $0.site?.caseInsensitiveCompare("YouTube") == .orderedSame
                && $0.type?.caseInsensitiveCompare("Trailer") == .orderedSame
                && $0.key?.isEmpty == false
        }
        let selected = candidates.first(where: { $0.official == true }) ?? candidates.first
        guard let key = selected?.key,
              var components = URLComponents(string: "https://www.youtube.com/watch") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "v", value: key)]
        return components.url
    }
}

struct TMDBTitleGenre: Decodable, Equatable {
    let name: String?
}

struct TMDBTitleCredits: Decodable, Equatable {
    let cast: [TMDBTitleCastMember]?
    let crew: [TMDBTitleCrewMember]?
}

struct TMDBTitleCastMember: Decodable, Equatable, Identifiable {
    let id: Int?
    let name: String?
    let character: String?
}

struct TMDBTitleCrewMember: Decodable, Equatable {
    let name: String?
    let job: String?
}

struct TMDBTitleCreator: Decodable, Equatable {
    let name: String?
}

struct TMDBTitleVideos: Decodable, Equatable {
    let results: [TMDBTitleVideo]?
}

struct TMDBTitleVideo: Decodable, Equatable {
    let key: String?
    let site: String?
    let type: String?
    let official: Bool?
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
