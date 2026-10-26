import Foundation

struct SceneBoxTorrentSearch: Sendable {
    private let sourceBases: [String]
    private let session: URLSession
    private let cache: SourceDiscoveryCache?
    private let endpointTimeout: TimeInterval
    private let fallbackDelay: TimeInterval

    init(
        sourceBases: [String] = [
            "https://torrentio.strem.fun/qualityfilter=unknown,other,cam,scr",
            "https://torrentio.strem.fun"
        ],
        session: URLSession = .shared,
        cache: SourceDiscoveryCache? = nil,
        endpointTimeout: TimeInterval = 6,
        fallbackDelay: TimeInterval = 0.5
    ) {
        let normalizedBases = sourceBases.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var seenBases = Set<String>()
        self.sourceBases = normalizedBases.filter { seenBases.insert($0).inserted }
        self.session = session
        self.cache = cache ?? (session === URLSession.shared ? .shared : nil)
        self.endpointTimeout = min(12, max(0.05, endpointTimeout.isFinite ? endpointTimeout : 6))
        self.fallbackDelay = min(2, max(0, fallbackDelay.isFinite ? fallbackDelay : 0.5))
    }

    func discover(
        for request: PlaybackSourceRequest,
        externalIDResolver: any PlaybackExternalIDResolving
    ) async -> StremioAddonDiscovery {
        guard request.isValid else {
            return Self.failedDiscovery("Torrentio", message: "The playback request is invalid.")
        }

        let imdbID: String?
        do {
            try Task.checkCancellation()
            if let existing = request.imdbID { imdbID = existing }
            else { imdbID = try await externalIDResolver.imdbID(for: request) }
        } catch is CancellationError {
            return Self.failedDiscovery("Torrentio", message: "Source search was cancelled.")
        } catch {
            return Self.failedDiscovery("Torrentio", message: error.localizedDescription)
        }

        guard let imdbID else {
            return StremioAddonDiscovery(
                sources: [],
                torrentDescriptors: [],
                providerStatuses: [
                    StremioAddonProviderStatus(
                        id: "scenebox-torrentio",
                        name: "Torrentio",
                        outcome: .identifierUnavailable
                    )
                ]
            )
        }

        let streamRequest = StremioStreamRequest(
            mediaType: request.mediaKind == .movie ? "movie" : "series",
            itemID: imdbID,
            seasonNumber: request.seasonNumber,
            episodeNumber: request.episodeNumber
        )
        guard streamRequest.isValid else {
            return Self.failedDiscovery("Torrentio", message: "The media identifier or episode coordinates are invalid.")
        }

        // A stalled configured endpoint must not delay a healthy fallback for its full timeout.
        // Staggered starts preserve fast configured replies; at most four requests are active.
        return await withTaskGroup(of: EndpointResult.self) { group in
            let maximumConcurrentRequests = 4
            var nextIndex = 0
            while nextIndex < min(maximumConcurrentRequests, sourceBases.count) {
                let index = nextIndex
                let base = sourceBases[index]
                group.addTask { await fetchEndpoint(base, request: streamRequest, delay: Double(index) * fallbackDelay) }
                nextIndex += 1
            }
            var lastFailure: String?
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return Self.failedDiscovery("Torrentio", message: "Source search was cancelled.")
                }
                if let discovery = Self.usableDiscovery(result.entries, imdbID: imdbID) {
                    group.cancelAll()
                    return discovery
                }
                if let failure = result.failure { lastFailure = failure }
                if nextIndex < sourceBases.count {
                    let base = sourceBases[nextIndex]
                    group.addTask { await fetchEndpoint(base, request: streamRequest, delay: 0) }
                    nextIndex += 1
                }
            }
            return StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: [
                StremioAddonProviderStatus(id: "scenebox-torrentio", name: "Torrentio",
                    outcome: lastFailure.map(StremioAddonProviderOutcome.failed) ?? .noSources)
            ])
        }
    }

    private func fetchEndpoint(_ base: String, request: StremioStreamRequest, delay: TimeInterval) async -> EndpointResult {
        do {
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            try Task.checkCancellation()
            return EndpointResult(entries: try await fetchStreams(from: base, request: request), failure: nil)
        } catch { return EndpointResult(entries: [], failure: error.localizedDescription) }
    }

    private struct EndpointResult: Sendable {
        let entries: [StremioStreamEntry]
        let failure: String?
    }

    private static func usableDiscovery(_ entries: [StremioStreamEntry], imdbID: String) -> StremioAddonDiscovery? {
        let sources = mapSources(entries, imdbID: imdbID)
        var seen = Set<String>()
        let descriptors = entries.compactMap { StremioTorrentDescriptor(stream: $0, providerName: "Torrentio") }
            .filter { seen.insert($0.id).inserted }
        guard !sources.isEmpty || !descriptors.isEmpty else { return nil }
        return StremioAddonDiscovery(sources: sources, torrentDescriptors: descriptors, providerStatuses: [
            StremioAddonProviderStatus(id: "scenebox-torrentio", name: "Torrentio",
                outcome: .found(directSourceCount: sources.count, torrentSourceCount: descriptors.count))
        ])
    }

    private func fetchStreams(from base: String, request: StremioStreamRequest) async throws -> [StremioStreamEntry] {
        let allowedIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:")
        guard let encodedID = request.protocolID.addingPercentEncoding(withAllowedCharacters: allowedIDCharacters),
              let url = URL(string: "\(base)/stream/\(request.mediaType)/\(encodedID).json"),
              StremioAddonClient.isSafeHTTPSURL(url) else {
            throw StremioAddonClientError.invalidRequest
        }

        if let data = await cache?.data(for: url.absoluteString, resource: .streams),
           let response = try? JSONDecoder().decode(StremioStreamResponse.self, from: data) {
            try Task.checkCancellation()
            PlaybackDiagnostics.record("torrentio.streams.cache_hit", details: ["entry_count": String(response.streams.count)])
            return response.streams
        }
        var networkRequest = URLRequest(url: url)
        networkRequest.timeoutInterval = endpointTimeout
        networkRequest.cachePolicy = .reloadIgnoringLocalCacheData
        networkRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        networkRequest.setValue("CineNex/SceneBox-TorrentSearch", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await SourceDiscoveryNetworking.data(for: networkRequest, session: session,
                delegate: StremioHTTPSRedirectDelegate(), timeout: endpointTimeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw StremioAddonClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              StremioAddonClient.isSafeHTTPSURL(finalURL) else {
            throw StremioAddonClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StremioAddonClientError.httpStatus(http.statusCode)
        }
        guard data.count <= 2_000_000 else {
            throw StremioAddonClientError.invalidResponse
        }
        let streams = try JSONDecoder().decode(StremioStreamResponse.self, from: data).streams
        let cacheControl = http.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
        if !cacheControl.contains("no-store"), !cacheControl.contains("no-cache") {
            await cache?.store(data, for: url.absoluteString, resource: .streams, lifetime: streams.isEmpty ? 10 : 120)
        }
        PlaybackDiagnostics.record("torrentio.streams.received", details: ["host": url.host ?? "unknown", "entry_count": String(streams.count)])
        return streams
    }

    private static func mapSources(_ entries: [StremioStreamEntry], imdbID: String) -> [PlaybackSource] {
        entries.compactMap { entry in
            guard let url = entry.validatedPlaybackURL else { return nil }
            let title = [entry.title, entry.name, entry.description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "Torrentio stream"
            let text = [entry.name, entry.title, entry.description].compactMap { $0 }.joined(separator: " ")
            let quality = ["2160P", "4K", "1080P", "720P", "480P", "SD", "HD"]
                .first(where: { text.uppercased().contains($0) })
            return PlaybackSource(
                id: "scenebox-torrentio-\(imdbID)-\(url.absoluteString)",
                providerID: "torrentio",
                providerName: "Torrentio",
                title: title,
                url: url,
                qualityLabel: quality,
                languageCode: nil,
                subtitleLanguages: [],
                supportsNativePlayback: true,
                providerPriority: 80
            )
        }
    }

    private static func failedDiscovery(_ name: String, message: String) -> StremioAddonDiscovery {
        StremioAddonDiscovery(
            sources: [],
            torrentDescriptors: [],
            providerStatuses: [
                StremioAddonProviderStatus(
                    id: "scenebox-torrentio",
                    name: name,
                    outcome: .failed(message)
                )
            ]
        )
    }
}
