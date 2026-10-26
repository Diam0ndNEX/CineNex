import Foundation

struct SceneBoxTorrentSearch: Sendable {
    private let sourceBases: [String]
    private let session: URLSession

    init(
        sourceBases: [String] = [
            "https://torrentio.strem.fun/qualityfilter=unknown,other,cam,scr",
            "https://torrentio.strem.fun"
        ],
        session: URLSession = .shared
    ) {
        self.sourceBases = Array(NSOrderedSet(array: sourceBases.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        })) as? [String] ?? sourceBases
        self.session = session
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
            imdbID = try await externalIDResolver.imdbID(for: request)
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

        var lastFailure: String?
        for base in sourceBases {
            do {
                let entries = try await fetchStreams(from: base, request: streamRequest)
                try Task.checkCancellation()
                if entries.isEmpty { continue }
                let sources = Self.mapSources(entries, imdbID: imdbID)
                var seen = Set<String>()
                let descriptors = entries.compactMap {
                    StremioTorrentDescriptor(stream: $0, providerName: "Torrentio")
                }.filter { seen.insert($0.id).inserted }
                let outcome: StremioAddonProviderOutcome = sources.isEmpty && descriptors.isEmpty
                    ? .noSources
                    : .found(directSourceCount: sources.count, torrentSourceCount: descriptors.count)
                return StremioAddonDiscovery(
                    sources: sources,
                    torrentDescriptors: descriptors,
                    providerStatuses: [
                        StremioAddonProviderStatus(
                            id: "scenebox-torrentio",
                            name: "Torrentio",
                            outcome: outcome
                        )
                    ]
                )
            } catch is CancellationError {
                return StremioAddonDiscovery(
                    sources: [],
                    torrentDescriptors: [],
                    providerStatuses: [
                        StremioAddonProviderStatus(
                            id: "scenebox-torrentio",
                            name: "Torrentio",
                            outcome: .failed("Source search was cancelled.")
                        )
                    ]
                )
            } catch {
                lastFailure = error.localizedDescription
            }
        }

        return StremioAddonDiscovery(
            sources: [],
            torrentDescriptors: [],
            providerStatuses: [
                StremioAddonProviderStatus(
                    id: "scenebox-torrentio",
                    name: "Torrentio",
                    outcome: lastFailure.map(StremioAddonProviderOutcome.failed) ?? .noSources
                )
            ]
        )
    }

    private func fetchStreams(from base: String, request: StremioStreamRequest) async throws -> [StremioStreamEntry] {
        let allowedIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:")
        guard let encodedID = request.protocolID.addingPercentEncoding(withAllowedCharacters: allowedIDCharacters),
              let url = URL(string: "(base)/stream/(request.mediaType)/(encodedID).json"),
              StremioAddonClient.isSafeHTTPSURL(url) else {
            throw StremioAddonClientError.invalidRequest
        }

        var networkRequest = URLRequest(url: url)
        networkRequest.timeoutInterval = 6
        networkRequest.cachePolicy = .reloadIgnoringLocalCacheData
        networkRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        networkRequest.setValue("CineNex/SceneBox-TorrentSearch", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: networkRequest, delegate: StremioHTTPSRedirectDelegate())
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
        return try JSONDecoder().decode(StremioStreamResponse.self, from: data).streams
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
                id: "scenebox-torrentio-(imdbID)-(url.absoluteString)",
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
