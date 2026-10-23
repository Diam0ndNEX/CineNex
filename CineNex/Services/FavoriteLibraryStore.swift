import Foundation

final class FavoriteLibraryStore {
    static let shared = FavoriteLibraryStore()

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.favoriteSnapshots") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> [String: MediaItem] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: MediaItem].self, from: data) else {
            return [:]
        }
        return decoded.filter { key, item in
            key == item.id && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func save(_ item: MediaItem) {
        guard !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        var snapshots = load()
        snapshots[item.id] = item
        persist(snapshots)
    }

    func remove(itemID: String) {
        var snapshots = load()
        guard snapshots.removeValue(forKey: itemID) != nil else { return }
        persist(snapshots)
    }

    private func persist(_ snapshots: [String: MediaItem]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
