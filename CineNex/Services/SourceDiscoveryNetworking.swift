import CryptoKit
import Foundation

/// Discovery has a separate connection pool so launch-time catalog/artwork requests cannot queue
/// a title-ID lookup behind unrelated shared-session traffic. No cookies or credentials persist.
enum SourceDiscoveryNetworking {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    static func usesApplicationCache(_ candidate: URLSession) -> Bool {
        candidate === session || candidate === URLSession.shared
    }

    /// A task-group timeout still awaits the losing child after cancelAll(). A stalled transport
    /// completion queue can therefore outlive that "deadline". This bridge completes the caller
    /// exactly once at the deadline/cancel point and cancels the dataTask without awaiting its callback.
    static func data(for request: URLRequest, session: URLSession,
                     delegate: (any URLSessionTaskDelegate)? = nil,
                     timeout: TimeInterval) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let requestID = String(UUID().uuidString.prefix(8))
        let started = ProcessInfo.processInfo.systemUptime
        let resource = request.url?.path.contains("/stream/") == true ? "streams"
            : (request.url?.path.hasSuffix("manifest.json") == true ? "manifest" : "identifier")
        let details = ["request": requestID, "host": request.url?.host ?? "unknown", "resource": resource]
        PlaybackDiagnostics.record("discovery.http.start", details: details)
        let gate = DiscoveryRequestCompletion()
        do {
            let payload: DiscoveryHTTPPayload = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    gate.install(continuation, timeout: timeout)
                    let task = session.dataTask(with: request) { data, response, error in
                        if let error { gate.complete(.failure(error)) }
                        else if let data, let response { gate.complete(.success(DiscoveryHTTPPayload(data: data, response: response))) }
                        else { gate.complete(.failure(URLError(.badServerResponse))) }
                    }
                    task.delegate = delegate
                    task.priority = URLSessionTask.highPriority
                    gate.start(task)
                }
            } onCancel: { gate.complete(.failure(CancellationError()), cancellingTransport: true) }
            try Task.checkCancellation()
            PlaybackDiagnostics.record("discovery.http.end", details: details.merging([
                "elapsed_ms": String(Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)),
                "bytes": String(payload.data.count), "outcome": "response"
            ]) { _, new in new })
            return (payload.data, payload.response)
        } catch {
            PlaybackDiagnostics.record("discovery.http.end", details: details.merging([
                "elapsed_ms": String(Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)),
                "outcome": error is CancellationError ? "cancelled" : "error",
                "code": String((error as NSError).code), "domain": (error as NSError).domain
            ]) { _, new in new })
            throw error
        }
    }
}

private struct DiscoveryHTTPPayload: Sendable {
    let data: Data
    let response: URLResponse
}

/// The only unchecked boundary is Foundation's callback API: the lock owns all mutable state,
/// atomically removes the continuation/task/timer before invoking any of them, and ignores late
/// callbacks. No network work, cancellation, or continuation resume occurs while the lock is held.
/// Keep this bridge until URLSession provides a cancellation completion independent of its delegate queue.
private final class DiscoveryRequestCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DiscoveryHTTPPayload, Error>?
    private var task: URLSessionDataTask?
    private var timer: DispatchSourceTimer?
    private var finished = false
    private var earlyError: Error?

    func install(_ continuation: CheckedContinuation<DiscoveryHTTPPayload, Error>, timeout: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + max(0.01, timeout.isFinite ? timeout : 12))
        timer.setEventHandler { [weak self] in
            self?.complete(.failure(URLError(.timedOut)), cancellingTransport: true)
        }
        lock.lock()
        let wasFinished = finished
        let error = earlyError
        if !wasFinished { self.continuation = continuation; self.timer = timer }
        lock.unlock()
        timer.resume()
        if wasFinished {
            timer.cancel()
            continuation.resume(throwing: error ?? CancellationError())
        }
    }

    func start(_ task: URLSessionDataTask) {
        lock.lock()
        let wasFinished = finished
        if !wasFinished { self.task = task }
        lock.unlock()
        if wasFinished { task.cancel() } else { task.resume() }
    }

    func complete(_ result: Result<DiscoveryHTTPPayload, Error>, cancellingTransport: Bool = false) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        if case .failure(let error) = result { earlyError = error }
        let continuation = self.continuation
        let task = self.task
        let timer = self.timer
        self.continuation = nil
        self.task = nil
        self.timer = nil
        lock.unlock()
        timer?.cancel()
        continuation?.resume(with: result)
        if cancellingTransport { task?.cancel() }
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
