import Foundation

enum SceneBoxStreamPicker {
    static func ordered(
        _ streams: [StremioTorrentDescriptor],
        preferredResolution: String = "1080p",
        debridEnabled: Bool = false
    ) -> [StremioTorrentDescriptor] {
        let wanted = preferredResolution.lowercased()
        return streams.sorted { lhs, rhs in
            rank(lhs, wanted: wanted, debridEnabled: debridEnabled)
                > rank(rhs, wanted: wanted, debridEnabled: debridEnabled)
        }
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
