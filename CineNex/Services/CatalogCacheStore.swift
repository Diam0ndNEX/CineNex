import Foundation

struct CachedCatalogSnapshot: Codable, Equatable {
    let items: [MediaItem]
    let savedAt: Date
}

final class CatalogCacheStore {
    static let shared = CatalogCacheStore()

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.catalogCache") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> CachedCatalogSnapshot? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(CachedCatalogSnapshot.self, from: data),
              !snapshot.items.isEmpty,
              snapshot.items.allSatisfy({
                  !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            return nil
        }
        return snapshot
    }

    func save(_ items: [MediaItem], savedAt: Date = Date()) {
        let validItems = items.filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !validItems.isEmpty,
              Set(validItems.map(\.id)).count == validItems.count else {
            return
        }

        let snapshot = CachedCatalogSnapshot(items: validItems, savedAt: savedAt)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
