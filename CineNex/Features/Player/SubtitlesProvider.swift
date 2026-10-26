import Foundation
import CryptoKit

actor SubtitlesProvider {
    private let base = "https://opensubtitles-v3.strem.io"

    func subtitles(context: SubtitleContext) async -> [SubtitleTrack] {
        var identifier = context.imdbID
        if context.type == "series", let season = context.season, let episode = context.episode {
            identifier += ":\(season):\(episode)"
        }
        guard let url = URL(string: "\(base)/subtitles/\(context.type)/\(identifier).json") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let cacheURL = Self.directory.appendingPathComponent("list-\(Self.digest(identifier)).json")
        let data: Data

        if let fetched = try? await URLSession.shared.data(for: request).0 {
            data = fetched
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? fetched.write(to: cacheURL, options: .atomic)
        } else if let cached = try? Data(contentsOf: cacheURL) {
            data = cached
        } else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["subtitles"] as? [[String: Any]] else {
            return []
        }

        var seen = Set<String>()
        var tracks: [SubtitleTrack] = []
        for entry in raw {
            guard let urlText = entry["url"] as? String,
                  let url = URL(string: urlText),
                  let language = entry["lang"] as? String else {
                continue
            }
            let id = (entry["id"] as? String) ?? urlText
            guard seen.insert(id).inserted else { continue }
            tracks.append(SubtitleTrack(id: id, languageCode: language, url: url))
        }

        return tracks.sorted { rank($0.languageCode) < rank($1.languageCode) }
    }

    func download(_ track: SubtitleTrack) async throws -> URL {
        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneExpiredFiles(in: directory)

        let file = directory.appendingPathComponent(
            "\(track.languageCode)-\(Self.digest(track.id)).\(Self.fileExtension(for: track.url))"
        )
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }

        var request = URLRequest(url: track.url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        try data.write(to: file, options: .atomic)
        return file
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CineNexSubtitles", isDirectory: true)
    }

    private static func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ["srt", "vtt", "ass", "ssa", "sub"].contains(ext) ? ext : "srt"
    }

    private var didPrune = false

    private func pruneExpiredFiles(in directory: URL) {
        guard !didPrune else { return }
        didPrune = true
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func rank(_ code: String) -> Int {
        SubtitleLanguage.common.firstIndex { $0.code == code } ?? Int.max
    }
}
