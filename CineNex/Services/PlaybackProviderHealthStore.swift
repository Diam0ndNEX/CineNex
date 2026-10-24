import Foundation

struct PlaybackProviderHealth: Codable, Equatable, Identifiable, Sendable {
    var id: String { providerID }

    let providerID: String
    var consecutiveFailures: Int
    var lastFailureAt: Date?
    var nextRetryAt: Date?
    var lastErrorMessage: String?
    var lastSuccessAt: Date?

    var isCoolingDown: Bool {
        guard let nextRetryAt else { return false }
        return nextRetryAt > Date()
    }
}

actor PlaybackProviderHealthStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let baseCooldown: TimeInterval
    private let maximumCooldown: TimeInterval
    private var records: [String: PlaybackProviderHealth]

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "cinenex.playbackProviderHealth",
        baseCooldown: TimeInterval = 30,
        maximumCooldown: TimeInterval = 1_800
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.baseCooldown = max(1, baseCooldown.isFinite ? baseCooldown : 30)
        self.maximumCooldown = max(self.baseCooldown, maximumCooldown.isFinite ? maximumCooldown : 1_800)
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PlaybackProviderHealth].self, from: data) {
            var sanitized: [String: PlaybackProviderHealth] = [:]
            for record in decoded {
                let providerID = record.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !providerID.isEmpty,
                      record.consecutiveFailures >= 0,
                      sanitized[providerID] == nil else {
                    continue
                }

                let failures = min(record.consecutiveFailures, 30)
                let cleanedMessage = record.lastErrorMessage?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = cleanedMessage.flatMap { value in
                    value.isEmpty ? nil : String(value.prefix(300))
                }
                sanitized[providerID] = PlaybackProviderHealth(
                    providerID: providerID,
                    consecutiveFailures: failures,
                    lastFailureAt: record.lastFailureAt,
                    nextRetryAt: failures == 0 ? nil : record.nextRetryAt,
                    lastErrorMessage: failures == 0 ? nil : message,
                    lastSuccessAt: record.lastSuccessAt
                )
            }
            self.records = sanitized
            let sanitizedValues = sanitized.values.sorted {
                $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending
            }
            let originalValues = decoded.sorted {
                $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending
            }
            if sanitizedValues != originalValues,
               let normalizedData = try? JSONEncoder().encode(sanitizedValues) {
                defaults.set(normalizedData, forKey: storageKey)
            }
        } else {
            self.records = [:]
        }
    }

    func shouldQuery(providerID: String, at date: Date = Date()) -> Bool {
        guard let id = normalizedID(providerID),
              let retryAt = records[id]?.nextRetryAt else {
            return normalizedID(providerID) != nil
        }
        return retryAt <= date
    }

    func recordSuccess(providerID: String, at date: Date = Date()) {
        guard let id = normalizedID(providerID) else { return }
        var record = records[id] ?? PlaybackProviderHealth(
            providerID: id,
            consecutiveFailures: 0,
            lastFailureAt: nil,
            nextRetryAt: nil,
            lastErrorMessage: nil,
            lastSuccessAt: nil
        )
        record.consecutiveFailures = 0
        record.nextRetryAt = nil
        record.lastErrorMessage = nil
        record.lastSuccessAt = date
        records[id] = record
        persist()
    }

    func recordFailure(providerID: String, message: String, at date: Date = Date()) {
        guard let id = normalizedID(providerID) else { return }
        var record = records[id] ?? PlaybackProviderHealth(
            providerID: id,
            consecutiveFailures: 0,
            lastFailureAt: nil,
            nextRetryAt: nil,
            lastErrorMessage: nil,
            lastSuccessAt: nil
        )
        record.consecutiveFailures = min(record.consecutiveFailures + 1, 30)
        record.lastFailureAt = date
        record.nextRetryAt = date.addingTimeInterval(cooldown(for: record.consecutiveFailures))
        let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        record.lastErrorMessage = cleanedMessage.isEmpty ? "Provider request failed." : String(cleanedMessage.prefix(300))
        records[id] = record
        persist()
    }

    func health(for providerID: String) -> PlaybackProviderHealth? {
        guard let id = normalizedID(providerID) else { return nil }
        return records[id]
    }

    func allRecords() -> [PlaybackProviderHealth] {
        records.values.sorted {
            $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending
        }
    }

    func remove(providerID: String) {
        guard let id = normalizedID(providerID), records.removeValue(forKey: id) != nil else { return }
        persist()
    }

    private func cooldown(for failures: Int) -> TimeInterval {
        let exponent = Double(min(max(failures - 1, 0), 20))
        return min(baseCooldown * pow(2, exponent), maximumCooldown)
    }

    private func normalizedID(_ providerID: String) -> String? {
        let id = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private func persist() {
        let values = records.values.sorted {
            $0.providerID.localizedStandardCompare($1.providerID) == .orderedAscending
        }
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
