import Foundation

struct StremioTorrentDescriptor: Equatable, Sendable, Identifiable {
    let infoHash: String
    let fileIndex: Int?
    let trackers: [URL]
    let magnetURL: URL
    let title: String
    let providerName: String

    let id: String
    let resolutionLabel: String?
    let reportedSeeders: Int?
    let sizeLabel: String?
    let reportedSizeBytes: Double?

    init?(
        infoHash: String?,
        fileIndex: Int?,
        trackers: [URL] = [],
        title: String = "Torrent source",
        providerName: String = "Stremio add-on",
        metadataText: String? = nil,
        seeders: Int? = nil,
        videoSize: Int64? = nil
    ) {
        guard let infoHash else { return nil }
        let normalizedHash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedHash.utf8.count == 40, normalizedHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
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
        let providerKey = self.providerName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: "-")
        self.id = "\(providerKey):\(normalizedHash):\(fileIndex.map(String.init) ?? "all")"
        let metadata = metadataText ?? self.title
        let lower = metadata.lowercased()
        self.resolutionLabel = ["2160p", "1080p", "720p", "480p", "360p"].first(where: lower.contains)
            ?? ((lower.contains("4k") || lower.contains("uhd")) ? "2160p" : nil)
        self.reportedSeeders = seeders.flatMap { $0 >= 0 ? $0 : nil }
            ?? Self.capture(Self.seedPattern, in: metadata).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        let size = Self.capture(Self.sizePattern, in: metadata)
        let explicitBytes = videoSize.flatMap { $0 >= 0 ? Double($0) : nil }
        self.reportedSizeBytes = explicitBytes ?? size.flatMap(Self.bytes)
        self.sizeLabel = explicitBytes.map { String(format: "%.2f GB", $0 / 1_000_000_000) } ?? size
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
            stream.title,
            stream.description,
            stream.behaviorHints?.filename,
            stream.name
        ].compactMap { value -> String? in
            guard let value else { return nil }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  !["torrent", "torrent stream", "magnet", "torrent source"].contains(cleaned.lowercased()),
                  !Self.isOpaqueTitle(cleaned) else {
                return nil
            }
            return cleaned
        }
        self.init(
            infoHash: stream.infoHash,
            fileIndex: stream.fileIndex,
            trackers: trackers,
            title: titleCandidates.first ?? "Torrent source",
            providerName: providerName,
            metadataText: [stream.title, stream.description, stream.name, stream.behaviorHints?.filename].compactMap { $0 }.joined(separator: "\n"),
            seeders: stream.seeders,
            videoSize: stream.behaviorHints?.videoSize
        )
    }
    private static let opaquePatterns = [
        #"(?i)^[0-9a-f]{32,64}$"#,
        #"(?i)^[0-9a-f]{8}-[0-9a-f-]{27,}$"#,
        #"(?i)^[0-9a-f]{12,}(?:[-_][0-9a-f]{4,})+$"#
    ].map { try! NSRegularExpression(pattern: $0) }

    private static func isOpaqueTitle(_ text: String) -> Bool {
        let value = (text as NSString).deletingPathExtension
        let range = NSRange(value.startIndex..., in: value)
        return opaquePatterns.contains { $0.firstMatch(in: value, range: range) != nil }
    }

    private static let seedPattern = try! NSRegularExpression(pattern: #"(?:👤|[Ss]eeders?\s*[:=]?)\s*([0-9][0-9,]*)"#)
    private static let sizePattern = try! NSRegularExpression(pattern: #"(?i)(?<![a-z0-9])([0-9]+(?:\.[0-9]+)?\s*(?:TiB|GiB|MiB|KiB|TB|GB|MB|KB|B))\b"#)

    private static func capture(_ pattern: NSRegularExpression, in text: String) -> String? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func bytes(_ label: String) -> Double? {
        let valueText = label.prefix { $0.isNumber || $0 == "." }
        let unit = label.dropFirst(valueText.count).trimmingCharacters(in: .whitespaces).uppercased()
        guard let value = Double(valueText), value.isFinite, value >= 0 else { return nil }
        let multipliers: [String: Double] = ["B": 1, "KB": 1_000, "MB": 1_000_000, "GB": 1_000_000_000,
            "TB": 1_000_000_000_000, "KIB": 1_024, "MIB": 1_048_576, "GIB": 1_073_741_824, "TIB": 1_099_511_627_776]
        guard let multiplier = multipliers[unit], (value * multiplier).isFinite else { return nil }
        return value * multiplier
    }

}
