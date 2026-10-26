import Foundation

/// Legacy generic ElfHosted-only configurations should also try Midnight.
/// Preserve deliberate, configured MediaFusion paths without adding extra instances.
enum MediaFusionEndpointPolicy {
    static func withFallbacks(_ endpoints: [URL]) -> [URL] {
        let mediaFusion = endpoints.filter { $0.host?.lowercased().contains("mediafusion") == true }
        let hasCustomConfiguration = mediaFusion.contains { $0.path != "/manifest.json" || $0.query != nil }
        var result = endpoints
        if !hasCustomConfiguration {
            result += [
                URL(string: "https://mediafusionfortheweebs.midnightignite.me/manifest.json")!,
                URL(string: "https://mediafusion.elfhosted.com/manifest.json")!
            ]
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.absoluteString).inserted }
    }
}
