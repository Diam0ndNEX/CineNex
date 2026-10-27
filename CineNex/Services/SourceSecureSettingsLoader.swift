import Foundation

struct SourceSecureSettings: Sendable {
    let manifestText: String?
    let tmdbToken: String?
    let manifestStorageUnavailable: Bool
}

/// SecItemCopyMatching/SecItemUpdate may synchronously wait for securityd. Never execute those IPCs
/// on the UI actor, and never let them gate built-in source discovery indefinitely. The worker is
/// coalesced until it actually returns (Security has no cancel API); each screen owns a timed waiter.
actor SourceSecureSettingsLoader {
    static let shared = SourceSecureSettingsLoader()
    private struct Waiter {
        let continuation: CheckedContinuation<SourceSecureSettings, Error>
        let timer: DispatchSourceTimer
    }
    private let read: @Sendable () -> SourceSecureSettings
    private var worker: Task<Void, Never>?
    private var waiters: [UUID: Waiter] = [:]

    init(read: @escaping @Sendable () -> SourceSecureSettings = {
        let started = ProcessInfo.processInfo.systemUptime
        PlaybackDiagnostics.record("discovery.secure_settings.read.start")
        let manifestText: String?
        let unavailable: Bool
        do { manifestText = try StremioAddonConfigurationStore.load(); unavailable = false }
        catch { manifestText = nil; unavailable = true }
        let token = TMDBTokenStore.load()
        PlaybackDiagnostics.record("discovery.secure_settings.read.end", details: [
            "elapsed_ms": String(Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)),
            "saved_providers": String(manifestText != nil), "catalog_token": String(token != nil),
            "storage_unavailable": String(unavailable)
        ])
        return SourceSecureSettings(manifestText: manifestText, tmdbToken: token,
                                    manifestStorageUnavailable: unavailable)
    }) {
        self.read = read
    }

    func load(timeout: TimeInterval = 2) async throws -> SourceSecureSettings {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
                timer.schedule(deadline: .now() + max(0.01, timeout.isFinite ? timeout : 2))
                timer.setEventHandler { [weak self] in Task { await self?.expire(id) } }
                waiters[id] = Waiter(continuation: continuation, timer: timer)
                timer.resume()
                if worker == nil {
                    let read = self.read
                    worker = Task.detached(priority: .userInitiated) {
                        let settings = read()
                        await self.complete(settings)
                    }
                }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    private func complete(_ settings: SourceSecureSettings) {
        worker = nil
        let current = waiters.values
        waiters.removeAll()
        for waiter in current {
            waiter.timer.cancel()
            waiter.continuation.resume(returning: settings)
        }
    }

    private func expire(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timer.cancel()
        PlaybackDiagnostics.record("discovery.secure_settings.timeout")
        waiter.continuation.resume(throwing: SettingsError.timedOut)
    }

    private func cancel(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timer.cancel()
        waiter.continuation.resume(throwing: CancellationError())
    }

    enum SettingsError: LocalizedError {
        case timedOut
        var errorDescription: String? {
            "Saved provider settings are taking too long to respond. Built-in providers remain available; Refresh retries your saved configuration."
        }
    }
}
