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
    @State private var searchText = ""
    @State private var selectedEpisode: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    seasonHeader
                    episodeStatus

                    if !episodes.isEmpty {
                        episodeControls
                    }

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Episode details unavailable", systemImage: "wifi.exclamationmark")
                                .font(.headline)
                            Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { Task { await loadEpisodes() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !isLoading && errorMessage == nil && episodes.isEmpty {
                        ContentUnavailableView(
                            "No episodes listed",
                            systemImage: "rectangle.stack",
                            description: Text("TMDB has not provided episode details for this season.")
                        )
                    } else if !episodes.isEmpty && visibleEpisodes.isEmpty {
                        ContentUnavailableView {
                            Label("No matching episodes", systemImage: "magnifyingglass")
                        } description: {
                            Text("Search by episode title or number, or reset your selection.")
                        } actions: {
                            Button("Show all episodes") { searchText = ""; selectedEpisode = nil }
                        }
                    }

                    ForEach(visibleEpisodes) { episode in
                        Button {
                            watchRequest = EpisodeWatchRequest(item: item, seasonNumber: season.seasonNumber, episodeNumber: episode.episodeNumber)
                        } label: {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Choose a source for this episode")
                    }
                }
                .padding(20)
            }
            .refreshable { await loadEpisodes() }
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

    private var visibleEpisodes: [TMDBSeasonEpisode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return episodes.filter { episode in
            (selectedEpisode == nil || episode.episodeNumber == selectedEpisode)
                && (query.isEmpty || episode.displayName.localizedCaseInsensitiveContains(query)
                    || String(episode.episodeNumber) == query)
        }
    }

    private var summaryCount: Int {
        episodes.filter { !($0.overview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.count
    }

    private var seasonHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            CachedPosterImage(url: season.posterURL ?? item.posterURL, fallbackSymbol: "tv", symbolSize: 32)
                .frame(width: 94, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.cineNexAccent)
                Text(season.displayName)
                    .font(.title.weight(.bold))
                HStack(spacing: 12) {
                    if let year = season.airYear { Text(String(year)) }
                    if let count = season.episodeCount, count > 0 {
                        Text("\(count) episodes")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                if let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var episodeStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isLoading ? "Fetching episode details" : "Episode guide", systemImage: "rectangle.stack.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                else { Text("\(episodes.count) loaded").font(.caption).foregroundStyle(.secondary) }
            }
            if !episodes.isEmpty {
                ProgressView(value: Double(summaryCount), total: Double(episodes.count))
                    .tint(Color.cineNexAccent)
                    .accessibilityLabel("Episode summary availability")
                    .accessibilityValue("\(summaryCount) of \(episodes.count) episodes have summaries")
                Text("Summaries available for \(summaryCount) of \(episodes.count) episodes · TMDB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isLoading {
                Text("Loading titles, stills and air dates from TMDB…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var episodeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find an episode by title or number", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search episodes")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear episode search")
                }
            }
            .padding(13)
            .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Text("\(visibleEpisodes.count) episodes")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("All episodes") { selectedEpisode = nil }
                    ForEach(episodes) { episode in
                        Button("E\(episode.episodeNumber) · \(episode.displayName)") {
                            selectedEpisode = episode.episodeNumber
                        }
                    }
                } label: {
                    Label(selectedEpisode.map { "Episode \($0)" } ?? "All episodes", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func episodeRow(_ episode: TMDBSeasonEpisode) -> some View {
        let overview = episode.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            CachedPosterImage(url: episode.stillURL, fallbackSymbol: "play.rectangle", symbolSize: 38)
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("Episode \(episode.episodeNumber)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(episode.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    episodeMetadata(episode)
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = episode.airDate, !date.isEmpty { Text(date) }
                        if let runtime = episode.runtimeLabel { Text(runtime) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(overview.isEmpty ? "No episode summary available." : overview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label("Choose source", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(Color.cineNexAccent)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.06)) }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func episodeMetadata(_ episode: TMDBSeasonEpisode) -> some View {
        HStack(spacing: 12) {
            if let date = episode.airDate, !date.isEmpty { Text(date) }
            if let runtime = episode.runtimeLabel { Text(runtime) }
            if let rating = episode.voteAverage, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadEpisodes() async {
        guard !isLoading else { return }
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
