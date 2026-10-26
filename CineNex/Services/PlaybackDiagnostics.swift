import Foundation

/// Bounded, serialized diagnostics that omit request URLs, configuration tokens and media names.
enum PlaybackDiagnostics {
    static let storageKey = "cinenex.playbackStartupEvents"
    private static let lock = NSRecursiveLock()
    private static let maximumEvents = 200
    private static let telemetryStorageKey = storageKey + ".telemetry"
    nonisolated(unsafe) private static var lastSampleTimes: [String: TimeInterval] = [:]

    static var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        return ((defaults.stringArray(forKey: storageKey) ?? [])
            + (defaults.stringArray(forKey: telemetryStorageKey) ?? [])).enumerated().sorted {
                let leftTime = $0.element.prefix(20)
                let rightTime = $1.element.prefix(20)
                return leftTime == rightTime ? $0.offset < $1.offset : leftTime < rightTime
            }.map(\.element)
    }

    static func beginAttempt(provider: String, fileIndex: Int?) {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        defaults.set(UUID().uuidString, forKey: "cinenex.playbackAttemptID")
        defaults.set(ProcessInfo.processInfo.systemUptime, forKey: "cinenex.playbackAttemptStart")
        record("playback.attempt.begin", details: ["provider": provider, "file_index": fileIndex.map(String.init) ?? "automatic"])
    }

    /// Sample hot-path telemetry separately so it cannot evict discovery, errors or lifecycle events.
    static func sample(_ stage: String, details: [String: String], interval: TimeInterval = 5) {
        lock.lock()
        defer { lock.unlock() }
        let key = (UserDefaults.standard.string(forKey: "cinenex.playbackAttemptID") ?? "none") + stage
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastSampleTimes[key], now - last < interval { return }
        if lastSampleTimes.count > 64 { lastSampleTimes.removeAll() }
        lastSampleTimes[key] = now
        append(stage, details: details, storage: telemetryStorageKey, limit: 80)
    }

    static func record(_ stage: String, details: [String: String] = [:]) {
        append(stage, details: details, storage: storageKey, limit: maximumEvents)
    }

    private static func append(_ stage: String, details: [String: String], storage: String, limit: Int) {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        let attempt = defaults.string(forKey: "cinenex.playbackAttemptID") ?? "none"
        let uptime = ProcessInfo.processInfo.systemUptime
        let start = defaults.double(forKey: "cinenex.playbackAttemptStart")
        let elapsed = start > 0 ? max(0, uptime - start) : 0
        let context = details.keys.sorted().map { "\($0)=\(redact(details[$0] ?? ""))" }.joined(separator: " ")
        let event = "\(Date().formatted(.iso8601)) · \(stage) [attempt=\(attempt.prefix(8)) elapsed=\(String(format: "%.3f", elapsed))s main=\(Thread.isMainThread) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)] \(context)"
        let stored = defaults.stringArray(forKey: storage) ?? []
        defaults.set(Array((stored + [event]).suffix(limit)), forKey: storage)
    }

    static var report: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        var lines = [
            "CineNex playback report v3", "App \(version) (\(build))",
            "OS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Physical memory \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MiB",
            "Generated \(Date().formatted(.iso8601))", "", "SWIFT / PROVIDER EVENTS"
        ]
        lines += events
        lines += ["", "NATIVE SESSION EVENTS (timestamp, attempt, stage, resident bytes, thread, detail)"]
        if let file = nativeLogURL,
           let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
            lines += text.split(separator: "\n").suffix(250).map(String.init)
        } else {
            lines.append("No native events recorded. Confirm the installed build contains the native startup patch.")
        }
        return lines.joined(separator: "\n")
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: telemetryStorageKey)
        lastSampleTimes.removeAll()
        UserDefaults.standard.removeObject(forKey: "cinenex.playbackAttemptID")
        UserDefaults.standard.removeObject(forKey: "cinenex.playbackAttemptStart")
        if let nativeLogURL { try? FileManager.default.removeItem(at: nativeLogURL) }
    }

    private static var nativeLogURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CineNex/Diagnostics/native-startup.jsonl")
    }

    private static func redact(_ value: String) -> String {
        let limited = String(value.prefix(500))
        return limited.replacingOccurrences(
            of: "[a-zA-Z][a-zA-Z0-9+.-]*://[^\\s]+", with: "[redacted-url]", options: .regularExpression
        )
    }
}
