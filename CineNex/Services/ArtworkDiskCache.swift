import Foundation
import CryptoKit

/// URL keys are hashed; browsing URLs and any embedded configuration are not written to filenames.
actor ArtworkDiskCache {
    static let shared = ArtworkDiskCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("CineNex/Artwork", isDirectory: true))
    private let directory: URL
    private let maximumBytes: Int64
    private let lifetime: TimeInterval
    private var pending: [URL: (id: UUID, task: Task<Data, Error>)] = [:]
    private var generation = UUID()

    init(directory: URL, maximumBytes: Int64 = 256 * 1_024 * 1_024, lifetime: TimeInterval = 7 * 24 * 3_600) {
        self.directory = directory
        self.maximumBytes = max(0, maximumBytes)
        self.lifetime = max(0, lifetime)
    }

    func data(for url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { throw URLError(.badURL) }
        if let cached = cachedData(for: url) { return cached }
        if let entry = pending[url] { return try await entry.task.value }
        let id = UUID()
        let requestGeneration = generation
        let task = Task<Data, Error> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.url?.scheme?.lowercased() == "https", data.count <= 20_000_000 else { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            if !(http.value(forHTTPHeaderField: "Cache-Control")?.lowercased().contains("no-store") ?? false) {
                store(data, for: url)
            }
            return data
        }
        pending[url] = (id, task)
        defer { if pending[url]?.id == id { pending[url] = nil } }
        return try await task.value
    }

    func cachedData(for url: URL, now: Date = Date()) -> Data? {
        let file = location(for: url)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let date = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(date) >= 0, now.timeIntervalSince(date) < lifetime else { return nil }
        return try? Data(contentsOf: file, options: .mappedIfSafe)
    }

    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty, data.count <= 20_000_000, Int64(data.count) <= maximumBytes else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: location(for: url), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            prune()
        } catch { /* Cache failure must not prevent displaying downloaded artwork. */ }
    }

    func invalidate(_ url: URL) { try? FileManager.default.removeItem(at: location(for: url)) }

    func clear() {
        generation = UUID()
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private func location(for url: URL) -> URL {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key)
    }

    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        for (url, size, date) in entries {
            if total > maximumBytes || Date().timeIntervalSince(date) >= lifetime {
                do { try FileManager.default.removeItem(at: url); total -= size } catch { }
            }
        }
    }
}
