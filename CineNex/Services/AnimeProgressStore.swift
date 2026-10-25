import Foundation
import Combine

@MainActor
final class AnimeProgressStore: ObservableObject {
    static let shared = AnimeProgressStore()

    @Published private(set) var watchedEpisodes: [Int: Int]
    @Published private(set) var trackedAnime: [AnimeTitle]

    private let defaults: UserDefaults
    private let storageKey: String
    private var titlesStorageKey: String { "\(storageKey).titles" }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "cinenex.animeProgress.v1"
    ) {
        let resolvedTitlesStorageKey = "\(storageKey).titles"
        self.defaults = defaults
        self.storageKey = storageKey

        let resolvedWatchedEpisodes: [Int: Int]
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Int: Int].self, from: data) {
            resolvedWatchedEpisodes = saved.reduce(into: [:]) { result, entry in
                if entry.key > 0, entry.value > 0 {
                    result[entry.key] = entry.value
                }
            }
        } else {
            resolvedWatchedEpisodes = [:]
        }
        watchedEpisodes = resolvedWatchedEpisodes

        if let data = defaults.data(forKey: resolvedTitlesStorageKey),
           let saved = try? JSONDecoder().decode([AnimeTitle].self, from: data) {
            trackedAnime = saved
                .filter { $0.id > 0 && resolvedWatchedEpisodes[$0.id, default: 0] > 0 }
                .reduce(into: [AnimeTitle]()) { result, anime in
                    if !result.contains(where: { $0.id == anime.id }) {
                        result.append(anime)
                    }
                }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } else {
            trackedAnime = []
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
            trackedAnime.removeAll { $0.id == anime.id }
        } else {
            watchedEpisodes[anime.id] = normalized
            if let index = trackedAnime.firstIndex(where: { $0.id == anime.id }) {
                trackedAnime[index] = anime
            } else {
                trackedAnime.append(anime)
            }
            trackedAnime.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        persist()
    }

    func resetProgress(for animeID: Int) {
        guard animeID > 0 else { return }
        watchedEpisodes.removeValue(forKey: animeID)
        trackedAnime.removeAll { $0.id == animeID }
        persist()
    }

    private func persist() {
        guard let progressData = try? JSONEncoder().encode(watchedEpisodes),
              let titlesData = try? JSONEncoder().encode(trackedAnime) else {
            return
        }
        defaults.set(progressData, forKey: storageKey)
        defaults.set(titlesData, forKey: titlesStorageKey)
    }
}
