import Foundation

struct EmbedPlaybackProvider: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let baseURL: URL
    let priority: Int
    let supportedMediaKinds: Set<PlaybackMediaKind>
    let moviePath: String
    let seriesPath: String
    let requiresTMDBID: Bool

    init(
        id: String,
        displayName: String,
        baseURL: URL,
        priority: Int,
        supportedMediaKinds: Set<PlaybackMediaKind> = [.movie, .series],
        moviePath: String = "movie/{id}",
        seriesPath: String = "tv/{id}/{season}/{episode}",
        requiresTMDBID: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.priority = priority
        self.supportedMediaKinds = supportedMediaKinds
        self.moviePath = moviePath
        self.seriesPath = seriesPath
        self.requiresTMDBID = requiresTMDBID
    }

    func embedURL(for request: PlaybackSourceRequest) -> URL? {
        guard request.isValid,
              supportedMediaKinds.contains(request.mediaKind),
              let baseHost = baseURL.host,
              baseURL.scheme?.lowercased() == "https" else {
            return nil
        }

        if requiresTMDBID {
            guard let tmdbID = request.tmdbID, tmdbID > 0 else {
                return nil
            }
        }

        let identifier = request.tmdbID.map(String.init) ?? request.title
        let pathTemplate: String
        switch request.mediaKind {
        case .movie:
            pathTemplate = moviePath
        case .series:
            guard let seasonNumber = request.seasonNumber,
                  let episodeNumber = request.episodeNumber,
                  seasonNumber >= 0,
                  episodeNumber > 0 else {
                return nil
            }
            pathTemplate = seriesPath
        }

        let segmentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encodedSegments = pathTemplate.split(separator: "/", omittingEmptySubsequences: false).map { templateSegment -> String in
            let value: String
            switch templateSegment {
            case "{id}":
                value = identifier
            case "{season}":
                value = String(request.seasonNumber ?? 0)
            case "{episode}":
                value = String(request.episodeNumber ?? 0)
            default:
                value = String(templateSegment)
            }
            return value.addingPercentEncoding(withAllowedCharacters: segmentCharacters) ?? ""
        }

        guard !encodedSegments.isEmpty,
              !encodedSegments.contains(where: { $0.isEmpty }) else {
            return nil
        }

        let relativePath = encodedSegments.joined(separator: "/")
        let result = baseURL.appendingPathComponent(relativePath)
        guard result.host?.lowercased() == baseHost.lowercased(),
              result.scheme?.lowercased() == "https",
              result.user == nil,
              result.password == nil else {
            return nil
        }
        return result
    }
}

enum EmbedPlaybackProviderCatalog {
    static let candidates: [EmbedPlaybackProvider] = [
        EmbedPlaybackProvider(
            id: "vidsrc-to",
            displayName: "VidSrc",
            baseURL: URL(string: "https://vidsrc.to/embed/")!,
            priority: 100
        ),
        EmbedPlaybackProvider(
            id: "vidsrc-cc",
            displayName: "VidSrc (alternate)",
            baseURL: URL(string: "https://vidsrc.cc/v2/embed/")!,
            priority: 90
        ),
        EmbedPlaybackProvider(
            id: "two-embed",
            displayName: "2Embed",
            baseURL: URL(string: "https://www.2embed.cc/embed/")!,
            priority: 80,
            moviePath: "{id}",
            seriesPath: "{id}/{season}/{episode}"
        )
    ]
}
