import SwiftUI

struct SeasonEpisodesView: View {
    let item: MediaItem
    let season: TMDBTitleSeason

    @Environment(\.dismiss) private var dismiss
    @State private var watchRequest: EpisodeWatchRequest?
    @State private var pendingDirectPlayback: MediaItem?
    @State private var activeDirectPlayback: MediaItem?
    @State private var episodes: [TMDBSeasonEpisode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && episodes.isEmpty {
                    ProgressView("Loading episodes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, episodes.isEmpty {
                    ContentUnavailableView {
                        Label("Episodes unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task { await loadEpisodes() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if episodes.isEmpty {
                    ContentUnavailableView(
                        "No episodes listed",
                        systemImage: "rectangle.stack",
                        description: Text("TMDB has not provided episode details for this season.")
                    )
                } else {
                    List(episodes) { episode in
                        Button {
                            watchRequest = EpisodeWatchRequest(item: item, seasonNumber: season.seasonNumber, episodeNumber: episode.episodeNumber)
                        } label: {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Choose a source for this episode")
                            .listRowBackground(Color.cineNexSurface)
                    }
                    .listStyle(.plain)
                    .overlay(alignment: .top) {
                        if isLoading {
                            ProgressView()
                                .padding(8)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.top, 8)
                        }
                    }
                }
            }
            .background(Color.cineNexBackground)
            .navigationTitle(season.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: "\(item.id)-\(season.seasonNumber)") {
                await loadEpisodes()
            }
        }
        .tint(Color.cineNexAccent)
        .sheet(item: $watchRequest, onDismiss: {
            if let pending = pendingDirectPlayback {
                pendingDirectPlayback = nil
                activeDirectPlayback = pending
            }
        }) { request in
            WatchHubView(
                item: request.item,
                onPlayDirect: { directItem in
                    pendingDirectPlayback = directItem
                    watchRequest = nil
                },
                onSelectItem: { recommendation in
                    watchRequest = EpisodeWatchRequest(item: recommendation, seasonNumber: 1, episodeNumber: 1)
                },
                initialSeasonNumber: request.seasonNumber,
                initialEpisodeNumber: request.episodeNumber
            )
        }
        .fullScreenCover(item: $activeDirectPlayback) { directItem in
            PlayerView(item: directItem, progressStore: PlaybackProgressStore.shared)
        }
    }

    private func episodeRow(_ episode: TMDBSeasonEpisode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CachedPosterImage(
                url: episode.stillURL,
                fallbackSymbol: "play.rectangle",
                symbolSize: 24
            )
            .frame(width: 112, height: 70)
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("E\(episode.episodeNumber) · \(episode.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let airDate = episode.airDate, !airDate.isEmpty {
                        Text(airDate)
                    }
                    if let runtime = episode.runtimeLabel {
                        Text(runtime)
                    }
                    if let rating = episode.voteAverage, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let overview = episode.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No episode summary available.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadEpisodes() async {
        guard let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            errorMessage = "Connect TMDB in Settings → Accounts & tracking to view season episodes."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            episodes = try await TMDBCatalogProvider(readAccessToken: token)
                .fetchSeasonEpisodes(for: item, seasonNumber: season.seasonNumber)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EpisodeWatchRequest: Identifiable {
    let item: MediaItem
    let seasonNumber: Int
    let episodeNumber: Int
    var id: String { "\(item.id)-\(seasonNumber)-\(episodeNumber)" }
}
