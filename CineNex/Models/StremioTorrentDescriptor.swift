import Foundation

struct StremioTorrentDescriptor: Equatable, Sendable, Identifiable {
    let infoHash: String
    let fileIndex: Int?
    let trackers: [URL]
    let magnetURL: URL
    let title: String
    let providerName: String

    var id: String {
        "\(infoHash):\(fileIndex.map(String.init) ?? "all")"
    }

    init?(
        infoHash: String?,
        fileIndex: Int?,
        trackers: [URL] = [],
        title: String = "Torrent source",
        providerName: String = "Stremio add-on"
    ) {
        guard let infoHash else { return nil }
        let normalizedHash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedHash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            return nil
        }
        if let fileIndex, fileIndex < 0 { return nil }

        let allowedTrackers = trackers.filter { tracker in
            guard let scheme = tracker.scheme?.lowercased(),
                  ["udp", "http", "https"].contains(scheme),
                  let host = tracker.host,
                  !host.isEmpty,
                  tracker.user == nil,
                  tracker.password == nil else {
                return false
            }
            return true
        }
        var seenTrackers = Set<String>()
        let normalizedTrackers = Array(allowedTrackers.filter {
            seenTrackers.insert($0.absoluteString).inserted
        }.prefix(20))

        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [
            URLQueryItem(name: "xt", value: "urn:btih:\(normalizedHash)")
        ] + normalizedTrackers.map { URLQueryItem(name: "tr", value: $0.absoluteString) }
        guard let magnetURL = components.url else { return nil }

        self.infoHash = normalizedHash
        self.fileIndex = fileIndex
        self.trackers = normalizedTrackers
        self.magnetURL = magnetURL
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = cleanedTitle.isEmpty ? "Torrent source" : cleanedTitle
        let cleanedProviderName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerName = cleanedProviderName.isEmpty ? "Stremio add-on" : cleanedProviderName
    }

    init?(stream: StremioStreamEntry, providerName: String = "Stremio add-on") {
        let trackers = (stream.sources ?? []).compactMap { source -> URL? in
            guard source.hasPrefix("tracker:") else { return nil }
            let value = String(source.dropFirst("tracker:".count))
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["udp", "http", "https"].contains(scheme),
                  let host = url.host,
                  !host.isEmpty,
                  url.user == nil,
                  url.password == nil else {
                return nil
            }
            return url
        }
        let titleCandidates = [
            stream.name,
            stream.title,
            stream.description,
            stream.behaviorHints?.filename
        ].compactMap { value -> String? in
            guard let value else { return nil }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  !["torrent", "torrent stream", "magnet", "torrent source"].contains(cleaned.lowercased()),
                  cleaned.range(of: "^[0-9a-f]{32,64}$", options: .regularExpression) == nil,
                  cleaned.range(of: "^[0-9a-f]{8}-[0-9a-f-]{27,}$", options: .regularExpression) == nil else {
                return nil
            }
            return cleaned
        }
        self.init(
            infoHash: stream.infoHash,
            fileIndex: stream.fileIndex,
            trackers: trackers,
            title: titleCandidates.first ?? "Torrent source",
            providerName: providerName
        )
    }
}
