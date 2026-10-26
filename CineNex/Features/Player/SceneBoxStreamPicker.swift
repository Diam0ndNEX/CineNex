import Foundation

enum SourceReleaseSort: String, CaseIterable, Identifiable {
    case balanced = "Balanced"
    case seeders = "Most seeders"
    case resolution = "Highest quality"
    case size = "Smallest file"
    var id: String { rawValue }
}

enum SceneBoxStreamPicker {
    static func ordered(
        _ streams: [StremioTorrentDescriptor],
        preferredResolution: String = "1080p",
        debridEnabled: Bool = false
    ) -> [StremioTorrentDescriptor] {
        let wanted = preferredResolution.lowercased()
        return streams.sorted { lhs, rhs in
            let left = rank(lhs, wanted: wanted, debridEnabled: debridEnabled)
            let right = rank(rhs, wanted: wanted, debridEnabled: debridEnabled)
            return left == right ? lhs.id < rhs.id : left > right
        }
    }

    /// Interleave providers before applying a limit so a prolific provider cannot hide another.
    static func balanced(_ streams: [StremioTorrentDescriptor], limit: Int = 48) -> [StremioTorrentDescriptor] {
        guard limit > 0 else { return [] }
        var providers: [String] = []
        var groups: [String: [StremioTorrentDescriptor]] = [:]
        var seen = Set<String>()
        for stream in streams where seen.insert(stream.id).inserted {
            if groups[stream.providerName] == nil { providers.append(stream.providerName) }
            groups[stream.providerName, default: []].append(stream)
        }
        for provider in providers { groups[provider] = ordered(groups[provider] ?? []) }
        var result: [StremioTorrentDescriptor] = []
        var index = 0
        while result.count < limit {
            var added = false
            for provider in providers {
                guard let values = groups[provider], index < values.count else { continue }
                result.append(values[index])
                added = true
                if result.count == limit { return result }
            }
            guard added else { break }
            index += 1
        }
        return result
    }

    static func filtered(
        _ streams: [StremioTorrentDescriptor],
        provider: String? = nil,
        quality: String? = nil,
        sort: SourceReleaseSort = .balanced
    ) -> [StremioTorrentDescriptor] {
        let matches = streams.filter { stream in
            (provider == nil || stream.providerName == provider)
                && (quality == nil || (resolution(for: stream) ?? "Unknown") == quality)
        }
        guard sort != .balanced else { return balanced(matches, limit: Int.max) }
        return matches.sorted { left, right in
            switch sort {
            case .balanced: return false
            case .seeders:
                let a = seeders(for: left) ?? -1, b = seeders(for: right) ?? -1
                if a != b { return a > b }
            case .resolution:
                let a = resolutionValue(left), b = resolutionValue(right)
                if a != b { return a > b }
            case .size:
                let a = sizeBytes(for: left) ?? .infinity, b = sizeBytes(for: right) ?? .infinity
                if a != b { return a < b }
            }
            return left.id < right.id
        }
    }

    static func sizeBytes(for stream: StremioTorrentDescriptor) -> Double? {
        guard let label = size(for: stream) else { return nil }
        let parts = label.uppercased().split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let value = Double(parts[0]), value.isFinite, value >= 0 else { return nil }
        let multiplier: Double
        switch parts[1] {
        case "TB": multiplier = 1_000_000_000_000
        case "TIB": multiplier = 1_099_511_627_776
        case "GB": multiplier = 1_000_000_000
        case "GIB": multiplier = 1_073_741_824
        case "MB": multiplier = 1_000_000
        case "MIB": multiplier = 1_048_576
        case "KB": multiplier = 1_000
        case "KIB": multiplier = 1_024
        case "B": multiplier = 1
        default: return nil
        }
        let bytes = value * multiplier
        return bytes.isFinite ? bytes : nil
    }

    private static func resolutionValue(_ stream: StremioTorrentDescriptor) -> Int {
        Int((resolution(for: stream) ?? "").replacingOccurrences(of: "p", with: "")) ?? 0
    }

    static func resolution(for stream: StremioTorrentDescriptor) -> String? {
        let text = stream.title.lowercased()
        if text.contains("2160p") || text.contains("4k") || text.contains("uhd") { return "2160p" }
        for resolution in ["1080p", "720p", "480p", "360p"] where text.contains(resolution) {
            return resolution
        }
        return nil
    }

    static func seeders(for stream: StremioTorrentDescriptor) -> Int? {
        let text = stream.title
        guard let range = text.range(of: "👤") else { return nil }
        let suffix = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    static func size(for stream: StremioTorrentDescriptor) -> String? {
        let text = stream.title
        guard let range = text.range(of: "💾") else { return nil }
        let suffix = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return suffix.split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ")
    }

    private static func rank(
        _ stream: StremioTorrentDescriptor,
        wanted: String,
        debridEnabled: Bool
    ) -> (Int, Int, Int) {
        let provider = stream.providerName.lowercased()
        let cached = (debridEnabled && (provider.contains("debrid") || provider.contains("stremthru"))) ? 1 : 0
        let seeders = seeders(for: stream) ?? 0
        let resolutionMatch = (resolution(for: stream) == wanted && seeders >= 5) ? 1 : 0
        return (cached, resolutionMatch, seeders)
    }
}
