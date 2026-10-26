import Foundation

enum SmartPlaybackCandidate: Sendable, Identifiable {
    case torrent(StremioTorrentDescriptor)
    case direct(PlaybackSource)

    var id: String {
        switch self {
        case .torrent(let release): return "torrent:\(release.infoHash):\(release.fileIndex.map(String.init) ?? "auto")"
        case .direct(let source): return source.url.absoluteString
        }
    }
    var title: String {
        switch self { case .torrent(let release): return release.providerName; case .direct(let source): return source.providerName }
    }
}

enum SmartPlaybackSelection {
    static func candidates(torrents: [StremioTorrentDescriptor], direct: [PlaybackSource],
                           preferredQuality: String = "1080p", maximumBytes: Double = 0,
                           hidingKnownDead: Bool = false) -> [SmartPlaybackCandidate] {
        let allowed = torrents.filter {
            (!hidingKnownDead || $0.reportedSeeders != 0)
                && (maximumBytes <= 0 || ($0.reportedSizeBytes.map { $0 <= maximumBytes } ?? true))
        }
        let ranked = SceneBoxStreamPicker.ordered(allowed, preferredResolution: preferredQuality)
        // Reported zero peers is a weaker candidate; unknown is not treated as zero.
        let healthy = ranked.filter { ($0.reportedSeeders ?? 1) > 0 }
        let zeroPeers = ranked.filter { $0.reportedSeeders == 0 }
        let choices = direct.filter { $0.isValid && $0.hasSecureWebURL && $0.supportsNativePlayback }.map(SmartPlaybackCandidate.direct)
            + (healthy + zeroPeers).map(SmartPlaybackCandidate.torrent)
        var seen = Set<String>()
        return choices.filter { seen.insert($0.id).inserted }
    }

    /// Sequential preparation avoids starting several native sessions or downloading several films.
    @MainActor
    static func firstReady(candidates: [SmartPlaybackCandidate], maximumAttempts: Int,
                           onAttempt: (SmartPlaybackCandidate, Int, Int) -> Void,
                           onFailure: (SmartPlaybackCandidate, String) -> Void,
                           discard: (PlaybackSource) async -> Void = { _ in },
                           prepare: (SmartPlaybackCandidate) async throws -> PlaybackSource) async throws -> PlaybackSource {
        let attempts = Array(candidates.prefix(min(5, max(1, maximumAttempts))))
        guard !attempts.isEmpty else { throw SelectionError.noCandidates }
        for (index, candidate) in attempts.enumerated() {
            try Task.checkCancellation()
            onAttempt(candidate, index + 1, attempts.count)
            do {
                let source = try await prepare(candidate)
                if Task.isCancelled { await discard(source); throw CancellationError() }
                return source
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                onFailure(candidate, error.localizedDescription)
            }
        }
        throw SelectionError.noneReady(attempts.count)
    }

    enum SelectionError: LocalizedError {
        case noCandidates, noneReady(Int), unreachableLink
        var errorDescription: String? {
            switch self {
            case .noCandidates: return "No releases match these filters. Try a different quality or provider."
            case .noneReady(let count): return "None of the \(count) checked releases could prepare playback. Choose another release or change your filters."
            case .unreachableLink: return "This direct link did not confirm a playable response. You can still try it manually."
            }
        }
    }
}

struct DirectPlaybackReadinessProbe: Sendable {
    let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 4
            configuration.timeoutIntervalForResource = 6
            self.session = URLSession(configuration: configuration)
        }
    }
    func confirm(_ source: PlaybackSource) async throws -> PlaybackSource {
        guard source.isValid, source.hasSecureWebURL, source.supportsNativePlayback else {
            throw SmartPlaybackSelection.SelectionError.unreachableLink
        }
        var request = URLRequest(url: source.url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        let (_, response) = try await session.data(for: request, delegate: StremioHTTPSRedirectDelegate())
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let mime = http.mimeType?.lowercased(),
              mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime == "application/vnd.apple.mpegurl"
                || mime == "application/x-mpegurl" || mime == "application/octet-stream" else {
            throw SmartPlaybackSelection.SelectionError.unreachableLink
        }
        return source
    }
}
