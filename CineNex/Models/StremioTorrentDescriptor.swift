import Foundation

struct StremioTorrentDescriptor: Equatable, Sendable, Identifiable {
    let infoHash: String
    let fileIndex: Int?
    let trackers: [URL]
    let magnetURL

    var id: String {
        "\(infoHash):\(fileIndex.map(String.init) ?? "all")"
    }

    init?(infoHash: String?, fileIndex: Int?, trackers: [URL] = []) {
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
    }

    init?(stream: StremioStreamEntry) {
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
        self.init(infoHash: stream.infoHash, fileIndex: stream.fileIndex, trackers: trackers)
    }
}
