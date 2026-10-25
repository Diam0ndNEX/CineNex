import AVKit
import SwiftUI

struct WatchHubView: View {
    let item: MediaItem
    let onPlayDirect: (MediaItem) -> Void
    let onSelectItem: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.defaultPlaybackProvider") private var defaultProviderID = "smart"
    @AppStorage("cinenex.stremioAddonManifestURLs") private var stremioAddonManifestURLs = "https://torrentio.strem.fun/manifest.json\nhttps://mediafusion.elfhosted.com/manifest.json"

    private static let defaultStremioAddonManifestURLText = "https://torrentio.strem.fun/manifest.json\nhttps://mediafusion.elfhosted.com/manifest.json"
    private static let defaultStremioAddonManifestURLs: [URL] = [
        URL(string: "https://torrentio.strem.fun/manifest.json")!,
        URL(string: "https://mediafusion.elfhosted.com/manifest.json")!
    ]
    @State private var selectedProvider: ResolvedEmbedSource?
    @State private var selectedDiscoveredSource: PlaybackSource?
    @State private var discoveredSources: [PlaybackSource] = []
    @State private var discoveredTorrentDescriptors: [StremioTorrentDescriptor] = []
    @State private var preparingTorrentDescriptorID: String?
    @State private var torrentPreparationMessage: String?
    @State private var torrentPreparationTask: Task<Void, Never>?
    @State private var searchingAddonSources = false
    @State private var addonSearchMessage: String?
    @State private var availableProviders: [ResolvedEmbedSource] = []
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
                EmbedWebPlaybackView(
                    title: item.title,
                    providerID: provider.provider.id,
                    providerName: provider.provider.displayName,
                    url: provider.url
                )
            }
            .sheet(item: $selectedDiscoveredSource) { source in
                DiscoveredSourcePlaybackView(source: source) {
                    discoveredSources.removeAll { $0.id == source.id }
                }
            }
            .task(id: item.id) {
                resolveSources()
                async let addonSearch: Void = searchStremioAddonSources()
                async let catalogDetails: Void = loadCatalogDetails()
                await addonSearch
                await catalogDetails
            }
            .onDisappear {
                torrentPreparationTask?.cancel()
                torrentPreparationTask = nil
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
                } else if defaultProviderID == "stremio-addons", let source = discoveredSources.first {
                    selectedDiscoveredSource = source
                } else if defaultProviderID == "libtorrent", let descriptor = discoveredTorrentDescriptors.first {
                    startTorrentPlayback(for: descriptor)
                } else if (defaultProviderID == "smart" || defaultProviderID == "direct"),
                          let source = discoveredSources.first {
                    selectedDiscoveredSource = source
                } else if (defaultProviderID == "smart" || defaultProviderID == "libtorrent"),
                          let descriptor = discoveredTorrentDescriptors.first {
                    startTorrentPlayback(for: descriptor)
                } else if let preferred = availableProviders.first(where: { $0.provider.id == defaultProviderID }) {
                    selectedProvider = preferred
                } else if let first = discoveredSources.first {
                    selectedDiscoveredSource = first
                } else if let descriptor = discoveredTorrentDescriptors.first {
                    startTorrentPlayback(for: descriptor)
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
            .disabled(availableProviders.isEmpty && discoveredSources.isEmpty && discoveredTorrentDescriptors.isEmpty && item.streamURL == nil)
            .accessibilityHint("Starts the preferred available playback source")

            Picker("Default source", selection: $defaultProviderID) {
                Text("Smart Default").tag("smart")
                if item.streamURL != nil {
                    Text("Direct playback").tag("direct")
                }
                ForEach(availableProviders) { source in
                    Text(source.provider.displayName).tag(source.provider.id)
                }
                if !discoveredSources.isEmpty {
                    Text("Stremio add-ons").tag("stremio-addons")
                }
                if !discoveredTorrentDescriptors.isEmpty {
                    Text("Torrent streaming").tag("libtorrent")
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
                    Text("Embed candidates are experimental. Stremio add-ons are queried for direct streams and torrent options.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(availableProviders.count + discoveredSources.count + discoveredTorrentDescriptors.count + (item.streamURL == nil ? 0 : 1)) sources")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cineNexSurface, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await searchStremioAddonSources() }
                } label: {
                    HStack(spacing: 10) {
                        if searchingAddonSources {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        Text(searchingAddonSources ? "Searching add-ons…" : "Search add-on sources")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cineNexSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(searchingAddonSources || preparingTorrentDescriptorID != nil)
                .accessibilityHint("Queries configured Stremio-compatible add-ons for this title or episode")

                Text("Torrentio and MediaFusion are preconfigured. Edit the manifest URLs to use your own instance or a configured add-on URL with custom filters or debrid settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Link("Configure Torrentio", destination: URL(string: "https://torrentio.strem.fun/configure")!)
                    Link("MediaFusion", destination: URL(string: "https://mediafusion.elfhosted.com")!)
                    Spacer(minLength: 0)
                    Button("Restore defaults") {
                        stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
                    }
                    .font(.caption.weight(.medium))
                }
                .font(.caption.weight(.medium))
                Text("One HTTPS manifest URL per line. Configured add-on URLs may include a custom path; keep private configuration URLs on your device.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: $stremioAddonManifestURLs)
                    .font(.caption.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 76, maxHeight: 120)
                    .padding(8)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Stremio add-on manifest URLs")
                    .onAppear {
                        if stremioAddonManifestURLs
                            .split(whereSeparator: \.isNewline)
                            .allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
                        }
                    }
                if let addonSearchMessage {
                    Text(addonSearchMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(discoveredSources) { source in
                    Button {
                        selectedDiscoveredSource = source
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: source.supportsNativePlayback ? "play.fill" : "play.rectangle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.cineNexAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text([source.providerName, source.qualityLabel].compactMap { $0 }.joined(separator: " · "))
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
                    .accessibilityLabel("Play source: \(source.title)")
                }
                
                ForEach(discoveredTorrentDescriptors) { descriptor in
                    Button {
                        startTorrentPlayback(for: descriptor)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.to.line.compact")
                                .font(.title2)
                                .foregroundStyle(Color.cineNexAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Torrent · \(String(descriptor.infoHash.prefix(12)))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(descriptor.fileIndex.map { "Torrent file index \($0)" } ?? "Auto-select a playable video file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preparingTorrentDescriptorID == descriptor.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.cineNexAccent)
                            }
                        }
                        .padding(12)
                        .background(Color.cineNexSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(preparingTorrentDescriptorID != nil)
                    .accessibilityLabel("Prepare torrent playback for \(descriptor.infoHash.prefix(12))")
                }
                if let torrentPreparationMessage {
                    Text(torrentPreparationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

            if availableProviders.isEmpty &&
                discoveredSources.isEmpty &&
                discoveredTorrentDescriptors.isEmpty &&
                !searchingAddonSources &&
                item.streamURL == nil {
                ContentUnavailableView(
                    "No compatible sources found",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(request.tmdbID == nil
                        ? "No verified direct source is attached. Configure a compatible Stremio add-on or provide a direct media URL."
                        : "No direct source was found. Check your Stremio add-ons or try another provider.")
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

    @MainActor
    private func searchStremioAddonSources() async {
        let configuredManifestURLs = stremioAddonManifestURLs
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> URL? in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty,
                      let url = URL(string: value),
                      url.scheme?.lowercased() == "https",
                      url.host != nil,
                      url.user == nil,
                      url.password == nil else { return nil }
                return url
            }
        let manifestURLs = configuredManifestURLs.isEmpty
            ? Self.defaultStremioAddonManifestURLs
            : configuredManifestURLs
        if configuredManifestURLs.isEmpty {
            stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
        }
        guard request.tmdbID != nil else {
            addonSearchMessage = "This catalog item has no TMDB identifier, so CineNex cannot resolve its IMDb ID for add-on lookup."
            discoveredSources = []
            discoveredTorrentDescriptors = []
            return
        }
        guard let token = TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            addonSearchMessage = "A TMDB Read Access Token is needed to resolve this title to the IMDb ID used by many add-ons."
            discoveredSources = []
            discoveredTorrentDescriptors = []
            return
        }

        await TorrentPlaybackSessionRegistry.shared.stopAll()
        searchingAddonSources = true
        addonSearchMessage = nil
        torrentPreparationMessage = nil
        discoveredSources = []
        discoveredTorrentDescriptors = []
        defer { searchingAddonSources = false }

        do {
            let provider = try StremioAddonPlaybackProvider(
                manifestURLs: manifestURLs,
                externalIDResolver: TMDBExternalIDResolver(readAccessToken: token)
            )
            let discovery = try await provider.discover(for: request)
            let torrentDescriptors = Array(
                discovery.torrentDescriptors.reduce(into: [StremioTorrentDescriptor]()) { result, descriptor in
                    if !result.contains(where: { $0.id == descriptor.id }) {
                        result.append(descriptor)
                    }
                }.prefix(12)
            )
            discoveredSources = discovery.sources
            discoveredTorrentDescriptors = torrentDescriptors
            if !discovery.sources.isEmpty, !torrentDescriptors.isEmpty {
                addonSearchMessage = "Found \(discovery.sources.count) direct source(s) and \(torrentDescriptors.count) torrent option(s). Torrent transfers start only when you select one."
            } else if !discovery.sources.isEmpty {
                addonSearchMessage = "Found \(discovery.sources.count) direct source(s). Availability and playback compatibility are not guaranteed until playback starts."
            } else if !torrentDescriptors.isEmpty {
                addonSearchMessage = "Found \(torrentDescriptors.count) torrent option(s). Select one to prepare native playback."
            } else {
                addonSearchMessage = "No playable direct URLs or valid torrent descriptors were returned. Add-ons may be unavailable or may require authentication."
            }
        } catch is CancellationError {
            await TorrentPlaybackSessionRegistry.shared.stopAll()
            addonSearchMessage = "Source search was cancelled."
            discoveredSources = []
            discoveredTorrentDescriptors = []
        } catch {
            addonSearchMessage = error.localizedDescription
            discoveredSources = []
            discoveredTorrentDescriptors = []
        }
    }

    @MainActor
    private func startTorrentPlayback(for descriptor: StremioTorrentDescriptor) {
        guard torrentPreparationTask == nil else { return }
        preparingTorrentDescriptorID = descriptor.id
        torrentPreparationMessage = "Preparing native playback. Torrent metadata may take a moment to load."
        torrentPreparationTask = Task {
            await prepareTorrentPlayback(for: descriptor)
        }
    }

    @MainActor
    private func prepareTorrentPlayback(for descriptor: StremioTorrentDescriptor) async {
        let engine = XITRIXTorrentPlaybackEngine(descriptor: descriptor)
        let provider = TorrentPlaybackProvider(engine: engine)
        defer {
            if preparingTorrentDescriptorID == descriptor.id {
                preparingTorrentDescriptorID = nil
            }
            torrentPreparationTask = nil
        }

        do {
            let sources = try await provider.findSources(for: request)
            try Task.checkCancellation()
            guard let source = sources.first else {
                await provider.stop()
                torrentPreparationMessage = "This torrent did not contain a playable file supported by CineNex."
                return
            }
            selectedDiscoveredSource = source
            torrentPreparationMessage = "Torrent source is ready. Opening the native player."
        } catch is CancellationError {
            await provider.stop()
            torrentPreparationMessage = "Torrent preparation was cancelled."
        } catch {
            await provider.stop()
            torrentPreparationMessage = error.localizedDescription
        }
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
    let providerID: String
    let providerName: String
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlaybackCleanerPolicy.enabledStorageKey) private var cleanerGloballyEnabled = true
    @AppStorage(PlaybackCleanerPolicy.disabledProvidersStorageKey) private var disabledProviderStorage = ""
    @State private var loadFailed = false
    @State private var reloadID = UUID()

    private var disabledProviderIDs: Set<String> {
        PlaybackCleanerPolicy.disabledProviderIDs(from: disabledProviderStorage)
    }

    private var cleanerEnabled: Bool {
        PlaybackCleanerPolicy.isEnabled(
            globallyEnabled: cleanerGloballyEnabled,
            providerID: providerID,
            disabledProviderIDs: disabledProviderIDs
        )
    }

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
                    EmbedWebView(url: url, cleanerEnabled: cleanerEnabled, onFailure: { loadFailed = true })
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Block ads & trackers", isOn: $cleanerGloballyEnabled)
                        Toggle(
                            "Disable for \(providerName)",
                            isOn: Binding(
                                get: { disabledProviderIDs.contains(providerID) },
                                set: { isDisabled in
                                    var updated = disabledProviderIDs
                                    if isDisabled {
                                        updated.insert(providerID)
                                    } else {
                                        updated.remove(providerID)
                                    }
                                    disabledProviderStorage = PlaybackCleanerPolicy.storedValue(for: updated)
                                }
                            )
                        )
                        Text("Filters known ad networks and rejects pop-up windows. Some providers may need filtering disabled.")
                            .font(.caption)
                    } label: {
                        Image(systemName: cleanerEnabled ? "shield.lefthalf.filled" : "shield.slash")
                    }
                    .accessibilityLabel("Playback Cleaner settings")

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
        .onChange(of: cleanerGloballyEnabled) { _, _ in
            loadFailed = false
            reloadID = UUID()
        }
        .onChange(of: disabledProviderStorage) { _, _ in
            loadFailed = false
            reloadID = UUID()
        }
    }
}


private struct DiscoveredSourcePlaybackView: View {
    let source: PlaybackSource
    let onTorrentSessionStopped: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlaybackCleanerPolicy.enabledStorageKey) private var cleanerGloballyEnabled = true
    @AppStorage(PlaybackCleanerPolicy.disabledProvidersStorageKey) private var disabledProviderStorage = ""
    @State private var player: AVPlayer

    private var cleanerEnabled: Bool {
        PlaybackCleanerPolicy.isEnabled(
            globallyEnabled: cleanerGloballyEnabled,
            providerID: source.providerID,
            disabledProviderIDs: PlaybackCleanerPolicy.disabledProviderIDs(from: disabledProviderStorage)
        )
    }

    init(source: PlaybackSource, onTorrentSessionStopped: @escaping () -> Void = {}) {
        self.source = source
        self.onTorrentSessionStopped = onTorrentSessionStopped
        _player = State(initialValue: AVPlayer(url: source.url))
    }

    var body: some View {
        NavigationStack {
            Group {
                if source.supportsNativePlayback {
                    NativePlaybackView(player: player)
                        .onAppear { player.play() }
                        .onDisappear {
                            player.pause()
                            Task { @MainActor in
                                if await TorrentPlaybackSessionRegistry.shared.stop(for: source.url) {
                                    onTorrentSessionStopped()
                                }
                            }
                        }
                        .background(.black)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    EmbedWebView(url: source.url, cleanerEnabled: cleanerEnabled, onFailure: {})
                        .background(.black)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sources") { dismiss() }
                }
            }
        }
        .tint(Color.cineNexAccent)
    }
}
