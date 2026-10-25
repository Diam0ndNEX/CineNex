import Foundation
import Combine

@MainActor
final class AnimeProgressStore: ObservableObject {
    static let shared = AnimeProgressStore()

    @Published private(set) var watchedEpisodes: [Int: Int]

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "cinenex.animeProgress.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Int: Int].self, from: data) {
            watchedEpisodes = saved.reduce(into: [:]) { result, entry in
                if entry.key > 0, entry.value > 0 {
                    result[entry.key] = entry.value
                }
            }
        } else {
            watchedEpisodes = [:]
        }
    }

    func watchedEpisodeCount(for animeID: Int) -> Int {
        max(0, watchedEpisodes[animeID] ?? 0)
    }

    func watchedEpisodeCount(for anime: AnimeTitle) -> Int {
        let count = watchedEpisodeCount(for: anime.id)
        return min(count, anime.episodeCount ?? 9_999)
    }

    func setWatchedEpisodeCount(_ count: Int, for anime: AnimeTitle) {
        guard anime.id > 0 else { return }
        let upperBound = max(0, anime.episodeCount ?? 9_999)
        let normalized = min(max(0, count), upperBound)
        if normalized == 0 {
            watchedEpisodes.removeValue(forKey: anime.id)
        } else {
            watchedEpisodes[anime.id] = normalized
        }
        persist()
    }

    func resetProgress(for animeID: Int) {
        guard animeID > 0 else { return }
        watchedEpisodes.removeValue(forKey: animeID)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(watchedEpisodes) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
