import Foundation

/// Release-name hints only. These labels do not claim decoder or display compatibility.
enum ReleaseTechnicalLabels {
    private static let groups: [[(String, NSRegularExpression)]] = {
        let patterns: [[(String, String)]] = [
        [("AV1", #"\bAV1\b"#), ("HEVC", #"\b(?:HEVC|[HX][ ._-]?265)\b"#),
         ("H.264", #"\b(?:AVC|[HX][ ._-]?264)\b"#)],
        [("Dolby Vision", #"\b(?:DOLBY[ ._-]?VISION|DOVI|DV)\b"#),
         ("HDR10+", #"\bHDR10\+"#), ("HDR10", #"\bHDR10\b"#), ("HDR", #"\bHDR\b"#)],
        [("Atmos", #"\bATMOS\b"#), ("TrueHD", #"\bTRUE[ ._-]?HD\b"#),
         ("DTS-HD", #"\bDTS[ ._-]?HD\b"#), ("DTS", #"\bDTS\b"#),
         ("DD+", #"\b(?:DDP|E[ ._-]?AC[ ._-]?3)\b"#), ("AAC", #"\bAAC\b"#)]
        ]
        return patterns.map { group in
            group.compactMap { entry -> (String, NSRegularExpression)? in
                guard let pattern = try? NSRegularExpression(pattern: entry.1, options: .caseInsensitive) else { return nil }
                return (entry.0, pattern)
            }
        }
    }()

    static func labels(in release: String) -> [String] {
        let text = String(release.prefix(8_192)).replacingOccurrences(of: "_", with: " ")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return groups.compactMap { group in
            group.first { $0.1.firstMatch(in: text, range: range) != nil }?.0
        }
    }
}
