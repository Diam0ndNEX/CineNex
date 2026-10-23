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
    let recommendations: TMDBTitleRecommendations?
    let seasons: [TMDBTitleSeason]?

    enum CodingKeys: String, CodingKey {
        case tagline
        case runtime
        case status
        case genres
        case credits
        case videos
        case recommendations
        case seasons
        case createdBy = "created_by"
        case episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
    }

    var seasonSummaries: [TMDBTitleSeason] {
        var seenNumbers = Set<Int>()
        return (seasons ?? []).filter { season in
            guard season.seasonNumber >= 0,
                  !(season.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                  seenNumbers.insert(season.seasonNumber).inserted else {
                return false
            }
            return true
        }.sorted { $0.seasonNumber < $1.seasonNumber }
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

    func recommendedItems(for kind: MediaKind) -> [MediaItem] {
        var seenIDs = Set<Int>()
        return (recommendations?.results ?? []).compactMap { result in
            guard result.id > 0, seenIDs.insert(result.id).inserted else { return nil }
            let titleValue = (kind == .movie ? result.title : result.name)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let titleValue, !titleValue.isEmpty else { return nil }
            let date = kind == .movie ? result.releaseDate : result.firstAirDate
            let year = date.flatMap { Int($0.prefix(4)) } ?? 0
            let overview = result.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
            let synopsis = overview?.isEmpty == false ? overview! : "No description is available from TMDB yet."
            let posterURL = result.posterPath.flatMap {
                URL(string: "https://image.tmdb.org/t/p/w500\($0)")
            }
            return MediaItem(
                id: "tmdb-\(kind == .movie ? "movie" : "tv")-\(result.id)",
                title: titleValue,
                kind: kind,
                year: year,
                genre: "Recommended",
                synopsis: synopsis,
                symbol: kind == .movie ? "film" : "tv",
                runtime: kind == .movie ? "Movie" : "Series",
                streamURL: nil,
                posterURL: posterURL,
                rating: result.voteAverage,
                externalID: result.id,
                metadataProvider: "tmdb"
            )
        }
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

struct TMDBTitleSeason: Decodable, Equatable, Identifiable {
    let tmdbID: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let episodeCount: Int?
    let seasonNumber: Int
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case tmdbID = "id"
        case name
        case overview
        case airDate = "air_date"
        case episodeCount = "episode_count"
        case seasonNumber = "season_number"
        case posterPath = "poster_path"
    }

    var displayName: String {
        if seasonNumber == 0 { return "Specials" }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Season \\(seasonNumber)" : trimmedName
    }

    var airYear: Int? {
        guard let airDate, airDate.count >= 4 else { return nil }
        return Int(airDate.prefix(4))
    }

    var posterURL: URL? {
        guard let posterPath, posterPath.hasPrefix("/") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\\(posterPath)")
    }

    var id: Int { tmdbID ?? seasonNumber }
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

struct TMDBTitleRecommendations: Decodable, Equatable {
    let results: [TMDBTitleRecommendation]?
}

struct TMDBTitleRecommendation: Decodable, Equatable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
