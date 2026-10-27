import Foundation

/// Local provider presentation preferences, independent of playback selection.
enum SourceProviderPins {
    static func decode(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8), data.count <= 32_768,
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        return values.compactMap { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !key.isEmpty && key.count <= 256 && seen.insert(key).inserted ? key : nil
        }.prefix(64).map { $0 }
    }

    static func toggled(_ provider: String, in text: String) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = decode(text)
        guard !key.isEmpty, key.count <= 256 else { return text }
        if values.contains(key) { values.removeAll { $0 == key } }
        else if values.count < 64 { values.append(key) }
        guard let data = try? JSONEncoder().encode(values) else { return text }
        return String(decoding: data, as: UTF8.self)
    }

    static func ordered(_ providers: [String], pinned: [String]) -> [String] {
        let available = Set(providers)
        return pinned.filter { available.contains($0) }
            + available.subtracting(pinned).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
