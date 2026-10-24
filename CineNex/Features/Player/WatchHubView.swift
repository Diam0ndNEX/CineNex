import SwiftUI

struct WatchHubView: View {
    let item: MediaItem
    let onPlayDirect: (MediaItem) -> Void
    let onSelectItem: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.defaultPlaybackProvider") private var defaultProviderID = "smart"
    @State private var selectedProvider: ResolvedEmbedSource?
    @State private var availableProviders: [ResolvedEmbedSource] = []
    @State private var internetArchiveSources: [PlaybackSource] = []
    @State private var internetArchiveSourcesLoading = false
    @State private var internetArchiveSourceErrorMessage: String?
    @State private var seasonNumber = 1
    @State private var episodeNumber = 1
    @State private var seasons: [TMDBTitleSeason] = []
    @State private var episodes: [TMDBSeasonEpisode] = []
    @State private var recommendations: [MediaItem] = []
    @State private var recommendationsLoading = false
    @State private var episodesLoading = false
    @State private var catalogErrorMessage: String?
    @State private var episodeErrorMessage: String?

    private var request: PlaybackSourceRequest {
        PlaybackSourceRequest(
            title: item.title,
            mediaKind: item.kind == .movie ? .movie : .series,
            tmdbID: item.metadataProvider == "tmdb" ? item.externalID : nil,
            releaseYear: item.year > 0 ? item.year : nil,
            seasonNumber: item.kind == .series ? seasonNumber : nil,
            episodeNumber: item.kind == .series ? episodeNumber : nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    quickActions
                    episodeSelection
                    providerSection
                    internetArchiveSection
                    recommendationsSection
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background(Color.cineNexBackground.ignoresSafeArea())
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedProvider) { provider in
                EmbedWebPlaybackView(title: item.title, url: provider.url)
            }
            .task(id: item.id) {
                resolveSources()
                async let archiveSearch: Void = loadInternetArchiveSources()
                await loadCatalogDetails()
                await archiveSearch
            }
        }
        .tint(Color.cineNexAccent)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [Color.cineNexAccent.opacity(0.65), Color.cineNexSurface, .black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                HStack(alignment: .bottom, spacing: 16) {
                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 42)
                        .frame(width: 112, height: 164)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .accessibilityAddTraits(.isHeader)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(([item.yearLabel, item.kind.rawValue, item.genre].compactMap { $0 }).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                        if let rating = item.rating {
                            Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.28))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                }
                .padding(16)
            }
            .frame(height: 218)
            .clipShape(RoundedRectangle(cornerRadius: 22))

            Text(item.synopsis)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if (defaultProviderID == "smart" || defaultProviderID == "direct"), item.streamURL != nil {
                    onPlayDirect(item)
                } else if (defaultProviderID == "smart" || defaultProviderID == "internet-archive"),
                          let source = internetArchiveSources.first {
                    playInternetArchiveSource(source)
                } else if let preferred = availableProviders.first(where: { $0.provider.id == defaultProviderID }) {
                    selectedProvider = preferred
                } else if let firstArchiveSource = internetArchiveSources.first {
                    playInternetArchiveSource(firstArchiveSource)
                } else if let first = availableProviders.first {
                    selectedProvider = first
                } else if item.streamURL != nil {
                    onPlayDirect(item)
                }
            } label: {
                Label("Quick Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .disabled(availableProviders.isEmpty && internetArchiveSources.isEmpty && item.streamURL == nil)
            .accessibilityHint("Starts the preferred available playback source")

            Picker("Default source", selection: $defaultProviderID) {
                Text("Smart Default").tag("smart")
                if item.streamURL != nil {
                    Text("Direct playback").tag("direct")
                }
                ForEach(availableProviders) { source in
                    Text(source.provider.displayName).tag(source.provider.id)
                }
                if !internetArchiveSources.isEmpty {
                    Text("Internet Archive · public-domain/CC").tag("internet-archive")
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Default playback source")
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Source options")
                        .font(.title3.bold())
                    Text("Embed candidates are experimental; Internet Archive results are checked against listed license metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(availableProviders.count + internetArchiveSources.count + (item.streamURL == nil ? 0 : 1)) sources")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cineNexSurface, in: Capsule())
            }

            if item.streamURL != nil {
                Button {
                    onPlayDirect(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(Color.cineNexAccent)
                            .frame(width: 44, height: 44)
                            .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Direct playback")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Play the supplied media URL with CineNex's native player")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.cineNexSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play directly: \(item.title)")
                .accessibilityHint("Plays the supplied media URL in CineNex's native player")
            }

            if availableProviders.isEmpty && internetArchiveSources.isEmpty && !internetArchiveSourcesLoading && item.streamURL == nil {
                ContentUnavailableView(
                    "No compatible sources found",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(request.tmdbID == nil
                        ? "No verified direct source is attached. Internet Archive searches public-domain and compatible Creative Commons films automatically."
                        : "No direct source was found. Internet Archive searches public-domain and compatible Creative Commons films automatically.")
                )
                .padding(.vertical, 8)
            }

            if !availableProviders.isEmpty {
                ForEach(availableProviders) { source in
                    Button {
                        selectedProvider = source
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.cineNexAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 7) {
                                    Text(source.provider.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if source.provider.id == defaultProviderID || (defaultProviderID == "smart" && item.streamURL == nil && source.id == availableProviders.first?.id) {
                                        Text("DEFAULT")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color.cineNexAccent)
                                    }
                                }
                                Text("Experimental candidate · not checked live")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color.cineNexSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Try \(source.provider.displayName) playback source")
                    .accessibilityHint("Opens an experimental source candidate that has not been checked for live availability")
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("You might also like")
                    .font(.title3.bold())
                Spacer()
                if recommendationsLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let catalogErrorMessage, recommendations.isEmpty {
                Text(catalogErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if recommendations.isEmpty && !recommendationsLoading {
                Text("Recommendations appear when TMDB metadata is available for this title.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(recommendations) { recommendation in
                            Button {
                                onSelectItem(recommendation)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    CachedPosterImage(
                                        url: recommendation.posterURL,
                                        fallbackSymbol: recommendation.symbol,
                                        symbolSize: 28
                                    )
                                    .frame(width: 124, height: 178)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    Text(recommendation.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 124, alignment: .leading)

                                    if let rating = recommendation.rating, rating > 0 {
                                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 124, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Watch \(recommendation.title)")
                            .accessibilityHint("Opens the Watch Hub for this recommendation")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var episodeSelection: some View {
        Group {
            if item.kind == .series {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose episode")
                        .font(.title3.bold())

                    if !seasons.isEmpty {
                        Picker("Season", selection: $seasonNumber) {
                            ForEach(seasons) { season in
                                Text(season.displayName).tag(season.seasonNumber)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: seasonNumber) { _, newValue in
                            episodeNumber = 1
                            Task { await loadEpisodes(for: newValue) }
                            resolveSources()
                        }
                    } else {
                        Stepper("Season \(seasonNumber)", value: $seasonNumber, in: 0...99)
                            .onChange(of: seasonNumber) { _, newValue in
                                episodeNumber = 1
                                Task { await loadEpisodes(for: newValue) }
                                resolveSources()
                            }
                    }

                    if !episodes.isEmpty {
                        Picker("Episode", selection: $episodeNumber) {
                            ForEach(episodes) { episode in
                                Text("E\(episode.episodeNumber) · \(episode.displayName)")
                                    .tag(episode.episodeNumber)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: episodeNumber) { _, _ in resolveSources() }

                        if let episode = episodes.first(where: { $0.episodeNumber == episodeNumber }),
                           let overview = episode.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !overview.isEmpty {
                            Text(overview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if episodesLoading {
                        ProgressView("Loading episodes…")
                            .font(.caption)
                    } else {
                        Text(episodeErrorMessage ?? "Episode metadata is unavailable. You can still choose a season and episode number manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("Episode \(episodeNumber)", value: $episodeNumber, in: 1...999)
                            .onChange(of: episodeNumber) { _, _ in resolveSources() }
                    }
                }
                .padding(16)
                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    @MainActor
    private func loadCatalogDetails() async {
        guard item.metadataProvider == "tmdb",
              let token = TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            catalogErrorMessage = item.metadataProvider == "tmdb"
                ? "Add your TMDB Read Access Token in Tracking to load recommendations and episode details."
                : "Live recommendations and episode details require a TMDB catalog item."
            return
        }

        recommendationsLoading = true
        catalogErrorMessage = nil
        defer { recommendationsLoading = false }

        do {
            let provider = TMDBCatalogProvider(readAccessToken: token)
            guard let details = try await provider.fetchDetails(for: item) else {
                catalogErrorMessage = "TMDB details are unavailable for this title."
                return
            }
            recommendations = details.recommendedItems(for: item.kind)
                .filter { $0.id != item.id }
                .prefix(12)
                .map { $0 }

            if item.kind == .series {
                seasons = details.seasonSummaries
                if let firstSeason = seasons.first {
                    seasonNumber = firstSeason.seasonNumber
                }
                await loadEpisodes(for: seasonNumber, provider: provider, token: token)
            }
        } catch is CancellationError {
            return
        } catch {
            catalogErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadEpisodes(for requestedSeason: Int, provider existingProvider: TMDBCatalogProvider? = nil, token existingToken: String? = nil) async {
        guard item.kind == .series else { return }
        guard let token = existingToken ?? TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            episodeErrorMessage = "Add your TMDB Read Access Token in Tracking to load episodes."
            episodes = []
            return
        }

        episodesLoading = true
        episodeErrorMessage = nil
        defer { episodesLoading = false }

        do {
            let provider = existingProvider ?? TMDBCatalogProvider(readAccessToken: token)
            let loadedEpisodes = try await provider.fetchSeasonEpisodes(for: item, seasonNumber: requestedSeason)
            guard seasonNumber == requestedSeason else { return }
            episodes = loadedEpisodes
            if !loadedEpisodes.contains(where: { $0.episodeNumber == episodeNumber }) {
                episodeNumber = loadedEpisodes.first?.episodeNumber ?? 1
            }
            resolveSources()
        } catch is CancellationError {
            return
        } catch {
            episodeErrorMessage = error.localizedDescription
            episodes = []
        }
    }


    private var internetArchiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open-license films")
                        .font(.title3.bold())
                    Text("Automatically searched through Internet Archive. Only exact-title MP4 results with an accepted public-domain or Creative Commons license label are shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if internetArchiveSourcesLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let internetArchiveSourceErrorMessage {
                Text(internetArchiveSourceErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(internetArchiveSources) { source in
                Button {
                    playInternetArchiveSource(source)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.cineNexAccent)
                            .frame(width: 44, height: 44)
                            .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(source.qualityLabel ?? "Internet Archive MP4")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Open-license label detected · native playback")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.cineNexAccent)
                    }
                    .padding(12)
                    .background(Color.cineNexSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(source.title) from Internet Archive")
                .accessibilityHint("Opens the direct MP4 source in CineNex's native player")
            }

            if internetArchiveSources.isEmpty && !internetArchiveSourcesLoading && internetArchiveSourceErrorMessage == nil {
                Text(item.kind == .series
                    ? "This integration currently supports films, not episodic series."
                    : "No exact-title public-domain or supported Creative Commons MP4 was found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func loadInternetArchiveSources() async {
        internetArchiveSources = []
        internetArchiveSourceErrorMessage = nil
        guard item.kind == .movie else { return }

        internetArchiveSourcesLoading = true
        defer { internetArchiveSourcesLoading = false }

        do {
            let result = try await PlaybackSourceCoordinator(
                providers: [InternetArchivePlaybackProvider()]
            ).search(for: request)
            internetArchiveSources = result.sources
        } catch is CancellationError {
            return
        } catch {
            internetArchiveSourceErrorMessage = "Internet Archive source discovery failed: \(error.localizedDescription)"
        }
    }

    private func playInternetArchiveSource(_ source: PlaybackSource) {
        let playableItem = MediaItem(
            id: "\(item.id)-internet-archive",
            title: item.title,
            kind: item.kind,
            year: item.year,
            genre: item.genre,
            synopsis: item.synopsis,
            symbol: item.symbol,
            runtime: item.runtime,
            streamURL: source.url,
            posterURL: item.posterURL,
            rating: item.rating,
            externalID: item.externalID,
            metadataProvider: item.metadataProvider
        )
        onPlayDirect(playableItem)
    }

    private func resolveSources() {
        let candidates = EmbedPlaybackProviderCatalog.candidates
        availableProviders = candidates.compactMap { provider in
            guard let url = provider.embedURL(for: request) else { return nil }
            return ResolvedEmbedSource(provider: provider, url: url)
        }.sorted {
            if $0.provider.priority != $1.provider.priority {
                return $0.provider.priority > $1.provider.priority
            }
            return $0.provider.displayName.localizedStandardCompare($1.provider.displayName) == .orderedAscending
        }
        if defaultProviderID != "smart",
           defaultProviderID != "internet-archive",
           !(defaultProviderID == "direct" && item.streamURL != nil),
           !availableProviders.contains(where: { $0.provider.id == defaultProviderID }) {
            defaultProviderID = "smart"
        }
    }
}

private struct ResolvedEmbedSource: Identifiable, Equatable {
    let provider: EmbedPlaybackProvider
    let url: URL

    var id: String { provider.id }
}

private struct EmbedWebPlaybackView: View {
    let title: String
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var loadFailed = false
    @State private var reloadID = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    ContentUnavailableView {
                        Label("Player couldn't load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("This source may be unavailable or incompatible with iOS. Return to the source list and try another provider.")
                    } actions: {
                        Button("Try Again") {
                            loadFailed = false
                            reloadID = UUID()
                        }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    EmbedWebView(url: url, onFailure: { loadFailed = true })
                        .id(reloadID)
                        .background(.black)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sources") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadFailed = false
                        reloadID = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload player")
                }
            }
        }
        .tint(Color.cineNexAccent)
    }
}
