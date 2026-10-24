import Foundation

enum PlaybackSourceKind: String, Codable, CaseIterable, Sendable {
    case directMedia
    case webEmbed
}

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
              let host = baseURL.host,
              baseURL.scheme?.lowercased() == "https" else {
            return nil
        }

        if requiresTMDBID && (request.tmdbID == nil || request.tmdbID! <= 0) {
            return nil
        }

        let identifier = request.tmdbID.map(String.init) ?? request.title
        let pathTemplate: String
        switch request.mediaKind {
        case .movie:
            pathTemplate = moviePath
        case .series:
            guard request.seasonNumber != nil, request.episodeNumber != nil else {
                return nil
            }
            pathTemplate = seriesPath
        }

        let path = pathTemplate
            .replacingOccurrences(of: "{id}", with: identifier)
            .replacingOccurrences(of: "{season}", with: String(request.seasonNumber ?? 0))
            .replacingOccurrences(of: "{episode}", with: String(request.episodeNumber ?? 0))
        let relativePath = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let result = baseURL.appendingPathComponent(relativePath)
        guard result.host?.lowercased() == host.lowercased(),
              result.scheme?.lowercased() == "https" else {
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
