import Combine
import Foundation

struct PlaybackProgress: Codable, Equatable, Identifiable {
    let itemID: String
    var position: Double
    var duration: Double
    var updatedAt: Date
    var itemSnapshot: MediaItem? = nil
    var id: String { itemID }

    var completionFraction: Double? {
        guard duration.isFinite, duration > 0 else { return nil }
        return min(1, max(0, position / duration))
    }
}

@MainActor
final class PlaybackProgressStore: ObservableObject {
    static let shared = PlaybackProgressStore()
    static let maximumStoredEntries = 100
    @Published private(set) var entries: [String: PlaybackProgress] = [:]
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.playbackProgress") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    var mostRecentlyWatched: [PlaybackProgress] {
        entries.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending
        }
    }

    func progress(for itemID: String) -> PlaybackProgress? { entries[itemID] }

    func record(itemID: String, position: Double, duration: Double, item: MediaItem? = nil) {
        guard !itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              position.isFinite, duration.isFinite, position >= 0, duration >= 0 else { return }
        let effectiveDuration = duration > 0 ? duration : (entries[itemID]?.duration ?? 0)
        if effectiveDuration > 0, position >= effectiveDuration - 30 {
            entries.removeValue(forKey: itemID)
            persist()
            return
        }
        guard position >= 5 else { return }
        entries[itemID] = PlaybackProgress(
            itemID: itemID,
            position: position,
            duration: effectiveDuration,
            updatedAt: Date(),
            itemSnapshot: item ?? entries[itemID]?.itemSnapshot
        )
        trimEntriesToLimit()
        persist()
    }

    func remove(itemID: String) {
        guard entries.removeValue(forKey: itemID) != nil else { return }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) else {
            entries = [:]
            return
        }

        entries = decoded.filter { key, value in
            let normalizedID = value.itemID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == value.itemID,
                  !normalizedID.isEmpty,
                  value.position.isFinite,
                  value.duration.isFinite,
                  value.position >= 0,
                  value.duration >= 0 else {
                return false
            }

            if value.duration > 0, value.position >= value.duration - 30 {
                return false
            }

            if let snapshot = value.itemSnapshot {
                guard snapshot.id == key,
                      !snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
            }

            return true
        }
        trimEntriesToLimit()
        if entries.count != decoded.count {
            persist()
        }
    }

    private func trimEntriesToLimit() {
        guard entries.count > Self.maximumStoredEntries else { return }
        let retained = entries.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending
        }.prefix(Self.maximumStoredEntries)
        entries = Dictionary(uniqueKeysWithValues: retained.map { ($0.itemID, $0) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
