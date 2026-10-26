import CryptoKit
import Foundation

/// Request.timeoutInterval limits idle time; this clock also bounds DNS, connection and a trickling body.
/// The losing URLSession.data task is cancelled before the operation returns.
enum SourceDiscoveryNetworking {
    static func data(for request: URLRequest, session: URLSession,
                     delegate: (any URLSessionTaskDelegate)? = nil,
                     timeout: TimeInterval) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: Payload.self) { group in
            group.addTask {
                let (data, response) = try await session.data(for: request, delegate: delegate)
                return Payload(data: data, response: response)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(max(0.01, timeout)))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return (result.data, result.response)
        }
    }

    private struct Payload: Sendable {
        let data: Data
        let response: URLResponse
    }
}

/// Small private metadata cache. Playback responses stay in memory because signed media URLs may expire.
/// Injected network sessions bypass the global cache unless the caller explicitly supplies one.
actor SourceDiscoveryCache {
    static let shared = SourceDiscoveryCache()
    enum Resource: String, Sendable { case manifest, streams, identifier }
    private struct Entry: Codable {
        let data: Data
        let expiresAt: Date
    }
    private var entries: [String: Entry] = [:]
    private var playbackKeys = Set<String>()
    private let directory: URL?
    private let maximumEntries = 128

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("CineNexSourceMetadata", isDirectory: true)) {
        self.directory = directory
    }

    func data(for key: String, resource: Resource, now: Date = Date()) -> Data? {
        let key = Self.cacheKey(key, resource: resource)
        if let entry = entries[key], entry.expiresAt > now { return entry.data }
        entries.removeValue(forKey: key)
        guard resource != .streams, let file = file(for: key),
              let data = try? Data(contentsOf: file), data.count <= 2_100_000,
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.expiresAt > now else { return nil }
        entries[key] = entry
        return entry.data
    }

    func store(_ data: Data, for key: String, resource: Resource,
               lifetime: TimeInterval, now: Date = Date()) {
        guard !data.isEmpty, data.count <= 2_000_000, lifetime > 0 else { return }
        let key = Self.cacheKey(key, resource: resource)
        let entry = Entry(data: data, expiresAt: now.addingTimeInterval(lifetime))
        if entries.count >= maximumEntries {
            entries = entries.filter { $0.value.expiresAt > now }
            if entries.count >= maximumEntries, let earliest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                entries.removeValue(forKey: earliest)
            }
        }
        entries[key] = entry
        playbackKeys.formIntersection(entries.keys)
        if resource == .streams { playbackKeys.insert(key) }
        guard resource != .streams, let directory, let file = file(for: key),
              let encoded = try? JSONEncoder().encode(entry) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoded.write(to: file, options: [.atomic, .completeFileProtection])
            // Keep disk usage bounded as well as the in-memory index.
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            if files.count > maximumEntries {
                let sorted = files.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                        < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
                for old in sorted.prefix(files.count - maximumEntries) { try? FileManager.default.removeItem(at: old) }
            }
        } catch { /* A cache write must never prevent discovery. */ }
    }

    func clearPlaybackResponses() {
        for key in playbackKeys { entries.removeValue(forKey: key) }
        playbackKeys.removeAll()
    }

    func clear() {
        entries.removeAll()
        playbackKeys.removeAll()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func file(for key: String) -> URL? { directory?.appendingPathComponent(key).appendingPathExtension("json") }
    private static func cacheKey(_ key: String, resource: Resource) -> String {
        SHA256.hash(data: Data((resource.rawValue + "|" + key).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One ID lookup serves simultaneous Torrentio/add-on searches. Each caller owns a cancellable waiter;
/// the producer is cancelled only after its final waiter leaves. Generation IDs reject late producers.
actor SourceIdentifierCache {
    static let shared = SourceIdentifierCache()
    private struct Pending {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<String?, Error>]
    }
    private let cache: SourceDiscoveryCache
    private var pending: [String: Pending] = [:]

    init(cache: SourceDiscoveryCache = .shared) { self.cache = cache }

    func resolve(key: String, loader: @escaping @Sendable () async throws -> String?) async throws -> String? {
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                if var existing = pending[key] {
                    existing.waiters[waiter] = continuation
                    pending[key] = existing
                    return
                }
                let generation = UUID()
                let task = Task {
                    do {
                        if let data = await cache.data(for: key, resource: .identifier),
                           let cached = String(data: data, encoding: .utf8),
                           cached.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil {
                            finish(key: key, generation: generation, result: .success(cached))
                            return
                        }
                        let value = try await loader()
                        try Task.checkCancellation()
                        if let value { await cache.store(Data(value.utf8), for: key, resource: .identifier, lifetime: 86_400) }
                        finish(key: key, generation: generation, result: .success(value))
                    } catch { finish(key: key, generation: generation, result: .failure(error)) }
                }
                pending[key] = Pending(generation: generation, task: task, waiters: [waiter: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiter: waiter) }
        }
    }

    private func finish(key: String, generation: UUID, result: Result<String?, Error>) {
        guard let item = pending[key], item.generation == generation else { return }
        pending.removeValue(forKey: key)
        for continuation in item.waiters.values { continuation.resume(with: result) }
    }

    private func cancel(key: String, waiter: UUID) {
        guard var item = pending[key], let continuation = item.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if item.waiters.isEmpty {
            pending.removeValue(forKey: key)
            item.task.cancel()
        } else { pending[key] = item }
    }
}
