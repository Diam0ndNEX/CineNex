import AVKit
import SwiftUI

struct WatchHubView: View {
    let item: MediaItem
    let onPlayDirect: (MediaItem) -> Void
    let onSelectItem: (MediaItem) -> Void

    init(
        item: MediaItem,
        onPlayDirect: @escaping (MediaItem) -> Void,
        onSelectItem: @escaping (MediaItem) -> Void,
        initialSeasonNumber: Int = 1,
        initialEpisodeNumber: Int = 1
    ) {
        self.item = item
        self.onPlayDirect = onPlayDirect
        self.onSelectItem = onSelectItem
        _seasonNumber = State(initialValue: max(0, initialSeasonNumber))
        _episodeNumber = State(initialValue: max(1, initialEpisodeNumber))
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.defaultPlaybackProvider") private var defaultProviderID = "smart"
    @State private var stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
    @State private var manifestStorageError: String?
    @State private var manifestConfigurationLoaded = false
    @State private var loadingProviderSettings = false
    @State private var sourceSearchTMDBToken: String?
    @State private var sourceSearchGeneration = UUID()
    @State private var sourceSearchTask: Task<Void, Never>?
    @State private var filteredTorrentDescriptors: [StremioTorrentDescriptor] = []
    @AppStorage("cinenex.smartPlaybackAttempts") private var smartPlaybackAttempts = 3
    @AppStorage("cinenex.smartPreferredQuality") private var smartPreferredQuality = "1080p"
    @AppStorage("cinenex.smartMaximumSizeGB") private var smartMaximumSizeGB = 0.0
    @AppStorage("cinenex.hideKnownDeadReleases") private var hideKnownDeadReleases = false
    @AppStorage("cinenex.pinnedSourceProviders") private var pinnedProvidersText = "[]"
    @AppStorage("cinenex.sourceCardDensity") private var sourceCardDensity = "comfortable"
    @AppStorage("cinenex.showSourceTechnicalLabels") private var showSourceTechnicalLabels = true
    @State private var releaseQuery = ""
    @State private var minimumSeeders = 0
    @State private var releaseFailures: [String: String] = [:]
    @State private var smartAttemptLabel: String?
    @State private var preparingTorrentTransfer = true
    @State private var discoveryStartedAt = Date()
    @State private var discoveryStage = "Contacting providers"


    private static let legacyDefaultStremioAddonManifestURLTexts: Set<String> = [
        "https://torrentio.strem.fun/manifest.json\nhttps://mediafusion.elfhosted.com/manifest.json",
        "https://torrentio.strem.fun/qualityfilter=unknown,other,cam,scr/manifest.json\nhttps://mediafusionfortheweebs.midnightignite.me/manifest.json"
    ]
    private static let defaultStremioAddonManifestURLText = "https://torrentio.strem.fun/qualityfilter=unknown,other,cam,scr/manifest.json\nhttps://mediafusion.elfhosted.com/manifest.json\nhttps://mediafusionfortheweebs.midnightignite.me/manifest.json"
    private static let defaultStremioAddonManifestURLs: [URL] = [
        URL(string: "https://torrentio.strem.fun/qualityfilter=unknown,other,cam,scr/manifest.json")!,
        URL(string: "https://mediafusion.elfhosted.com/manifest.json")!,
        URL(string: "https://mediafusionfortheweebs.midnightignite.me/manifest.json")!
    ]
    @State private var activePlaybackSheet: WatchPlaybackSheet?
    @State private var discoveredSources: [PlaybackSource] = []
    @State private var selectedSourceFilter = "All"
    @State private var discoveredTorrentDescriptors: [StremioTorrentDescriptor] = []
    @State private var preparingTorrentDescriptorID: String?
    @State private var torrentPreparationMessage: String?
    @State private var torrentPreparationStartedAt = Date()
    @State private var selectedTorrentProvider = "All providers"
    @State private var selectedQuality = "Any quality"
    @State private var releaseSort = SourceReleaseSort.balanced
    @State private var providerStatuses: [StremioAddonProviderStatus] = []
    @State private var showsProviderStatus = false
    @State private var showsAdvancedSettings = false
    @State private var showsEpisodeSelection = false
    @State private var torrentPreparationTask: Task<Void, Never>?
    @State private var torrentPreparationGeneration = UUID()
    @State private var searchingAddonSources = false
    @State private var sourceSearchCancelled = false
    @State private var discoveryCompletedProviders = 0
    @State private var discoveryExpectedProviders = 3
    @State private var cancellingPreparation = false
    @State private var addonSearchMessage: String?
    @State private var availableProviders: [ResolvedEmbedSource] = []
    @State private var seasonNumber = 1
    @State private var episodeNumber = 1
    @State private var seasons: [TMDBTitleSeason] = []
    @State private var episodes: [TMDBSeasonEpisode] = []
    @State private var episodesLoading = false
    @State private var episodeErrorMessage: String?

    private var request: PlaybackSourceRequest {
        PlaybackSourceRequest(
            title: item.title,
            mediaKind: item.kind == .movie ? .movie : .series,
            tmdbID: item.metadataProvider == "tmdb" ? item.externalID : nil,
            imdbID: item.externalIMDbID,
            releaseYear: item.year > 0 ? item.year : nil,
            seasonNumber: item.kind == .series ? seasonNumber : nil,
            episodeNumber: item.kind == .series ? episodeNumber : nil
        )
    }

    private var visibleDirectSources: [PlaybackSource] {
        selectedSourceFilter == "All" || selectedSourceFilter == "Direct" ? discoveredSources : []
    }

    private var visibleTorrentSources: [StremioTorrentDescriptor] {
        guard selectedSourceFilter == "All" || selectedSourceFilter == "Torrent" else { return [] }
        return filteredTorrentDescriptors
    }

    private var visibleEmbeddedSources: [ResolvedEmbedSource] {
        selectedSourceFilter == "All" || selectedSourceFilter == "Web" ? availableProviders : []
    }

    private var showsDirectPlayback: Bool {
        selectedSourceFilter == "All" || selectedSourceFilter == "Direct"
    }

    private var hasVisibleSources: Bool {
        !visibleDirectSources.isEmpty
            || !visibleTorrentSources.isEmpty
            || !visibleEmbeddedSources.isEmpty
            || (showsDirectPlayback && item.streamURL != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    hero
                    if item.kind == .series {
                        DisclosureGroup(isExpanded: $showsEpisodeSelection) {
                            episodeSelection
                        } label: {
                            Label("Season \(seasonNumber) · Episode \(episodeNumber)", systemImage: "rectangle.stack")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(preparingTorrentDescriptorID != nil)
                    }
                    quickActions
                    if preparingTorrentDescriptorID != nil { preparationPanel }
                    if let torrentPreparationMessage, preparingTorrentDescriptorID == nil {
                        Label(torrentPreparationMessage, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    providerSection.disabled(preparingTorrentDescriptorID != nil)
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background(Color.cineNexBackground.ignoresSafeArea())
            .navigationTitle("Play")
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        cancelSourceSearch()
                        cancelPlaybackPreparation()
                        dismiss()
                    }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh sources", systemImage: "arrow.clockwise") {
                        Task { await searchStremioAddonSources(forceRefresh: true) }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(searchingAddonSources || preparingTorrentDescriptorID != nil)
                }
            }
            .fullScreenCover(item: $activePlaybackSheet) { playbackSheet in
                switch playbackSheet {
                case .embedded(let provider):
                    EmbedWebPlaybackView(
                        title: item.title,
                        providerID: provider.provider.id,
                        providerName: provider.provider.displayName,
                        url: provider.url
                    )
                case .discovered(let source):
                    DiscoveredSourcePlaybackView(
                        source: source,
                        item: item,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber
                    ) {
                        discoveredSources.removeAll { $0.id == source.id }
                    }
                }
            }
            .task(id: request) {
                if !manifestConfigurationLoaded {
                    await loadStoredManifestConfiguration()
                    guard !Task.isCancelled else { return }
                    manifestConfigurationLoaded = true
                }
                resolveSources()
                await searchStremioAddonSources()
            }
            .task(id: sourceFilterRequest) {
                let filter = sourceFilterRequest
                filteredTorrentDescriptors = []
                let worker = Task.detached(priority: .userInitiated) {
                    let started = Date()
                    let candidates = filter.streams.filter { stream in
                        (filter.query.isEmpty || stream.title.localizedCaseInsensitiveContains(filter.query) || stream.providerName.localizedCaseInsensitiveContains(filter.query))
                            && (filter.minimumSeeders == 0 || (stream.reportedSeeders ?? -1) >= filter.minimumSeeders)
                            && (!filter.hideKnownDead || stream.reportedSeeders != 0)
                            && (filter.maximumBytes <= 0 || (stream.reportedSizeBytes.map { $0 <= filter.maximumBytes } ?? true))
                    }
                    let results = SceneBoxStreamPicker.filtered(candidates, provider: filter.provider, quality: filter.quality, sort: filter.sort)
                    PlaybackDiagnostics.record("discovery.filter.complete", details: [
                        "input_count": String(filter.streams.count), "output_count": String(results.count),
                        "elapsed_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                    ])
                    return results
                }
                let result = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                filteredTorrentDescriptors = result
            }
            .task(id: item.id) {
                await loadCatalogDetails()
            }
            .onDisappear {
                guard activePlaybackSheet == nil else { return }
                PlaybackDiagnostics.record("playback.preparation.cancel", details: ["reason": "source_screen_disappeared"])
                torrentPreparationTask?.cancel()
                torrentPreparationTask = nil
                torrentPreparationGeneration = UUID()
                cancelSourceSearch()
                Task {
                    await TorrentPlaybackSessionRegistry.shared.stopAll()
                }
            }
        }
        .tint(Color.cineNexAccent)
    }

    private var preparationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(smartAttemptLabel ?? "Preparing playback", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(context.date.timeIntervalSince(torrentPreparationStartedAt))))s")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if preparingTorrentTransfer { TorrentBufferingStatusView(compact: true) }
            else {
                ProgressView().progressViewStyle(.linear)
                Text("Checking the direct link response. Transfer statistics are available for torrent releases.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let torrentPreparationMessage {
                Text(torrentPreparationMessage).font(.caption).foregroundStyle(.secondary)
            }
            Button("Cancel preparation", role: .cancel) { cancelPlaybackPreparation() }
                .buttonStyle(.bordered)
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.cineNexAccent.opacity(0.35)) }
        .accessibilityElement(children: .contain)
    }

    @MainActor
    private func cancelPlaybackPreparation() {
        PlaybackDiagnostics.record("playback.preparation.cancel", details: ["reason": "user_selected_cancel"])
        torrentPreparationGeneration = UUID()
        torrentPreparationTask?.cancel()
        torrentPreparationTask = nil
        preparingTorrentDescriptorID = nil
        smartAttemptLabel = nil
        cancellingPreparation = false
        torrentPreparationMessage = "Preparation cancelled. You can choose another release."
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 30)
                .frame(width: 80, height: 118)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYBACK")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.cineNexAccent)
                Text(item.title)
                    .font(.title2.bold())
                    .lineLimit(3)
                Text([item.yearLabel, item.genre].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.kind == .series {
                    Text("Season \(seasonNumber) · Episode \(episodeNumber)")
                        .font(.caption.bold())
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasNativeSelection: Bool {
        !visibleTorrentSources.isEmpty || !visibleDirectSources.isEmpty || (showsDirectPlayback && item.streamURL != nil)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: playTopRelease) {
                HStack(spacing: 12) {
                    Image(systemName: hasNativeSelection ? "play.fill" : "magnifyingglass")
                    Text(hasNativeSelection ? "Find a ready release" : (searchingAddonSources ? "Finding releases…" : "Search again"))
                        .font(.headline)
                    Spacer()
                    if searchingAddonSources { ProgressView().tint(.white) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Color.cineNexAccent, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(preparingTorrentDescriptorID != nil || (searchingAddonSources && !hasNativeSelection))
            Text(hasNativeSelection ? "Checks a release’s startup data and tries another if it cannot prepare. Your filters and playback preferences apply." : "Sources are checked independently. You can play as soon as a result arrives.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var providerSection: some View {
        let pinned = Set(SourceProviderPins.decode(pinnedProvidersText))
        return LazyVStack(alignment: .leading, spacing: 18) {
            discoveryStatus
            sourceTypePicker
            if selectedSourceFilter == "All" || selectedSourceFilter == "Torrent" {
                providerChips
                releaseControls
            }
            HStack(alignment: .firstTextBaseline) {
                Text(selectedSourceFilter == "Web" ? "Web players" : "Available releases")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(selectedSourceFilter == "Web"
                     ? "\(visibleEmbeddedSources.count) alternatives"
                     : "\(visibleTorrentSources.count + visibleDirectSources.count + (showsDirectPlayback && item.streamURL != nil ? 1 : 0)) streams")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !visibleTorrentSources.isEmpty {
                ForEach(visibleTorrentSources) { descriptor in
                    SourceReleaseCard(
                        descriptor: descriptor,
                        isPreparing: preparingTorrentDescriptorID == descriptor.id,
                        isDisabled: preparingTorrentDescriptorID != nil,
                        statusMessage: releaseFailures[descriptor.id],
                        isPinned: pinned.contains(descriptor.providerName),
                        onTogglePin: { pinnedProvidersText = SourceProviderPins.toggled(descriptor.providerName, in: pinnedProvidersText) },
                        onPlay: { startTorrentPlayback(for: descriptor) }
                    )
                }
            }
            if showsDirectPlayback, item.streamURL != nil {
                directSourceRow(title: item.title, subtitle: "Supplied media link", quality: nil) {
                    onPlayDirect(item)
                }
            }
            ForEach(visibleDirectSources) { source in
                directSourceRow(title: source.title, subtitle: source.providerName, quality: source.qualityLabel) {
                    activePlaybackSheet = .discovered(source)
                }
            }
            if selectedSourceFilter == "Web" || selectedSourceFilter == "All" {
                webPlayers
            }
            if !searchingAddonSources, !loadingProviderSettings,
               visibleTorrentSources.isEmpty, visibleDirectSources.isEmpty,
               !(showsDirectPlayback && item.streamURL != nil),
               selectedSourceFilter != "Web" {
                emptySourceState
            } else if selectedSourceFilter == "Web", visibleEmbeddedSources.isEmpty, !searchingAddonSources, !loadingProviderSettings {
                ContentUnavailableView("No web alternatives", systemImage: "globe", description: Text("Choose All streams to return to native playback sources."))
            }
            providerStatusDetails
            advancedSettings
        }
    }

    private var discoveryStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(loadingProviderSettings ? "Loading saved providers" : (searchingAddonSources ? "Finding your streams" : (sourceSearchCancelled ? "Search stopped" : "Your sources")))
                    .font(.headline)
                Spacer()
                if searchingAddonSources {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(max(0, Int(context.date.timeIntervalSince(discoveryStartedAt))))s")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if loadingProviderSettings {
                ProgressView().progressViewStyle(.linear).tint(Color.cineNexAccent)
                Text("Reading saved provider configuration securely. Built-in providers start if storage is slow.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if searchingAddonSources {
                Text(discoveryStage).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(discoveryCompletedProviders), total: Double(max(discoveryExpectedProviders, 1)))
                    .tint(Color.cineNexAccent)
                HStack {
                    Text("\(discoveryCompletedProviders) / \(discoveryExpectedProviders) providers replied")
                    Spacer()
                    Button("Stop search", role: .cancel) { cancelSourceSearch() }
                }.font(.caption)
                Text("Discovery downloads provider lists only. Transfer speed appears when a release starts downloading.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Label("\(discoveredTorrentDescriptors.count) torrents", systemImage: "arrow.down.circle")
                Label("\(discoveredSources.count + (item.streamURL == nil ? 0 : 1)) direct", systemImage: "play.rectangle")
            }.font(.caption.weight(.medium))
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var sourceTypePicker: some View {
        ScrollView(.horizontal) {
            CineNexGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                sourceTypeButton("All", title: "All streams", symbol: "square.grid.2x2")
                sourceTypeButton("Torrent", title: "Torrents", symbol: "arrow.down.circle")
                sourceTypeButton("Direct", title: "Direct", symbol: "play.rectangle")
                sourceTypeButton("Web", title: "Web players", symbol: "globe")
            }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func sourceTypeButton(_ value: String, title: String, symbol: String) -> some View {
        Button { selectedSourceFilter = value } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .foregroundStyle(selectedSourceFilter == value ? Color.cineNexAccent : Color.primary)
                .cineNexGlass(in: Capsule(), prominent: selectedSourceFilter == value)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSourceFilter == value ? .isSelected : [])
    }

    private var providerChips: some View {
        let counts = Dictionary(grouping: discoveredTorrentDescriptors, by: \.providerName).mapValues(\.count)
        let pins = SourceProviderPins.decode(pinnedProvidersText)
        let providers = SourceProviderPins.ordered(Array(counts.keys), pinned: pins)
        return ScrollView(.horizontal) {
            CineNexGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    providerChip("All providers", count: discoveredTorrentDescriptors.count, pinned: false)
                    ForEach(providers, id: \.self) { provider in
                        providerChip(provider, count: counts[provider] ?? 0, pinned: pins.contains(provider))
                            .contextMenu {
                                Button(pins.contains(provider) ? "Unpin provider" : "Pin provider", systemImage: "pin") {
                                    pinnedProvidersText = SourceProviderPins.toggled(provider, in: pinnedProvidersText)
                                }
                            }
                    }
                }
            }.padding(.vertical, 4)
        }.scrollIndicators(.hidden)
    }

    private func providerChip(_ provider: String, count: Int, pinned: Bool) -> some View {
        Button { selectedTorrentProvider = provider } label: {
            HStack(spacing: 6) {
                if pinned { Image(systemName: "pin.fill") }
                Text(provider)
                Text(String(count)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold)).padding(.horizontal, 13).frame(minHeight: 44)
            .foregroundStyle(selectedTorrentProvider == provider ? Color.cineNexAccent : Color.primary)
            .cineNexGlass(in: Capsule(), prominent: selectedTorrentProvider == provider)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTorrentProvider == provider ? .isSelected : [])
        .accessibilityHint(provider == "All providers" ? "Show all torrent releases" : "Filter this provider; use the pin button on a release to keep the provider first")
    }

    private var releaseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter release names, codecs or languages", text: $releaseQuery)
                    .font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !releaseQuery.isEmpty { Button("Clear", systemImage: "xmark.circle.fill") { releaseQuery = "" }.labelStyle(.iconOnly) }
            }.padding(12).background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal) {
                CineNexGlassGroup(spacing: 8) { HStack(spacing: 8) { filterMenus } }
                    .padding(.vertical, 4)
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var filterMenus: some View {
        Menu {
            Picker("Provider", selection: $selectedTorrentProvider) {
                Text("All providers").tag("All providers")
                ForEach(Array(Set(discoveredTorrentDescriptors.map(\.providerName))).sorted(), id: \.self) { provider in
                    Text("\(provider) (\(discoveredTorrentDescriptors.filter { $0.providerName == provider }.count))").tag(provider)
                }
            }
        } label: {
            filterLabel(selectedTorrentProvider == "All providers" ? "Provider" : selectedTorrentProvider, symbol: "network")
        }
        Menu {
            Picker("Quality", selection: $selectedQuality) {
                Text("Any quality").tag("Any quality")
                ForEach(["2160p", "1080p", "720p", "480p", "360p", "Unknown"], id: \.self) { quality in
                    Text(quality == "2160p" ? "4K / 2160p" : quality).tag(quality)
                }
            }
        } label: {
            filterLabel(selectedQuality == "Any quality" ? "Quality" : selectedQuality, symbol: "viewfinder")
        }
        Menu {
            Picker("Minimum reported seeders", selection: $minimumSeeders) {
                Text("Any peer count").tag(0)
                ForEach([5, 20, 50], id: \.self) { Text("At least \($0) seeders").tag($0) }
            }
            Toggle("Hide reported zero seeders", isOn: $hideKnownDeadReleases)
            Picker("Maximum file size", selection: $smartMaximumSizeGB) {
                Text("Any size").tag(0.0)
                ForEach([2.0, 5.0, 10.0, 20.0, 40.0], id: \.self) { Text("Up to \(Int($0)) GB").tag($0) }
            }
            Text("Missing size or peer data stays unknown. Minimum-peer filters require reported counts.")
        } label: {
            filterLabel(minimumSeeders > 0 ? "\(minimumSeeders)+ seeders" : "More filters", symbol: "line.3.horizontal.decrease")
        }
        Menu {
            Picker("Release cards", selection: $sourceCardDensity) {
                Text("Comfortable").tag("comfortable")
                Text("Compact").tag("compact")
            }
            Toggle("Show codec, HDR and audio labels", isOn: $showSourceTechnicalLabels)
        } label: {
            filterLabel("Display", symbol: "rectangle.grid.1x2")
        }
        Menu {
            Picker("Sort releases", selection: $releaseSort) {
                ForEach(SourceReleaseSort.allCases) { order in Text(order.rawValue).tag(order) }
            }
        } label: {
            filterLabel(releaseSort.rawValue, symbol: "arrow.up.arrow.down")
        }
    }

    private func filterLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cineNexGlass(in: Capsule())
    }

    private func directSourceRow(title: String, subtitle: String, quality: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if let quality { SourceMetadataChip(title: quality, symbol: "viewfinder") }
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill").font(.caption)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(preparingTorrentDescriptorID != nil)
    }

    @ViewBuilder
    private var webPlayers: some View {
        if !visibleEmbeddedSources.isEmpty {
            DisclosureGroup {
                VStack(spacing: 10) {
                    Text("These open third-party websites. Their availability is not checked by the source search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(visibleEmbeddedSources) { source in
                        directSourceRow(title: source.provider.displayName, subtitle: "External web player", quality: nil) {
                            activePlaybackSheet = .embedded(source)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Web alternatives (\(visibleEmbeddedSources.count))", systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var emptySourceState: some View {
        ContentUnavailableView {
            Label("No matching releases", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(discoveredTorrentDescriptors.isEmpty && discoveredSources.isEmpty
                 ? "The providers returned no playable releases for this title. You can retry or review provider status below."
                 : "Try a different provider or quality, or reset your filters.")
        } actions: {
            Button("Reset filters") {
                selectedSourceFilter = "All"
                selectedTorrentProvider = "All providers"
                selectedQuality = "Any quality"
                releaseQuery = ""
                minimumSeeders = 0
                smartMaximumSizeGB = 0
                hideKnownDeadReleases = false
            }
            Button("Search again") { Task { await searchStremioAddonSources(forceRefresh: true) } }
        }
        .padding(.vertical, 12)
    }

    private var providerStatusDetails: some View {
        DisclosureGroup(isExpanded: $showsProviderStatus) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(providerStatuses) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.name).font(.caption.weight(.semibold))
                        Text(status.outcome.summary).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if providerStatuses.isEmpty {
                    Text(searchingAddonSources ? "Provider results will appear here." : "No provider result has been recorded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let addonSearchMessage {
                    Text(addonSearchMessage).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Provider status", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(Color.cineNexSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private var advancedSettings: some View {
        DisclosureGroup(isExpanded: $showsAdvancedSettings) {
            VStack(alignment: .leading, spacing: 12) {
                Text("One HTTPS manifest URL per line. Private configuration stays in Keychain on this device.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $stremioAddonManifestURLs)
                    .font(.system(.caption2, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(Color.cineNexBackground, in: RoundedRectangle(cornerRadius: 10))
                    .privacySensitive()
                    .accessibilityLabel("Provider manifest URLs")
                Button("Save and refresh sources", action: saveProviderConfiguration)
                    .buttonStyle(.borderedProminent)
                Button("Restore bundled providers") {
                    stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
                    saveProviderConfiguration()
                }
                HStack {
                    Link("Torrentio setup", destination: URL(string: "https://torrentio.strem.fun/configure")!)
                    Link("MediaFusion setup", destination: URL(string: "https://mediafusion.elfhosted.com/")!)
                }
                .font(.caption)
                if let manifestStorageError {
                    Label(manifestStorageError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Provider settings", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func playTopRelease() {
        guard torrentPreparationTask == nil else { return }
        let direct = visibleDirectSources + ((showsDirectPlayback && item.streamURL != nil) ? [PlaybackSource(
            id: "supplied-\(item.id)", providerID: "supplied", providerName: "Supplied media link", title: item.title,
            url: item.streamURL!, qualityLabel: nil, languageCode: nil, subtitleLanguages: [],
            supportsNativePlayback: true, providerPriority: 100)] : [])
        let choices = SmartPlaybackSelection.candidates(torrents: visibleTorrentSources, direct: direct,
            preferredQuality: smartPreferredQuality, maximumBytes: smartMaximumSizeGB * 1_000_000_000,
            hidingKnownDead: hideKnownDeadReleases).filter { candidate in
                switch candidate {
                case .torrent(let descriptor): return releaseFailures[descriptor.id] == nil
                case .direct: return releaseFailures[candidate.id] == nil
                }
            }
        guard !choices.isEmpty else {
            if !searchingAddonSources { Task { await searchStremioAddonSources() } }
            return
        }
        let preparationID = UUID()
        torrentPreparationGeneration = preparationID
        torrentPreparationStartedAt = Date()
        preparingTorrentDescriptorID = choices.first?.id
        torrentPreparationTask = Task {
            await prepareCandidates(choices, maximumAttempts: smartPlaybackAttempts, preparationID: preparationID)
        }
    }

    private func saveProviderConfiguration() {
        let lines = stremioAddonManifestURLs.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.allSatisfy({ line in
            guard let url = URL(string: line) else { return false }
            return StremioAddonClient.isSafeHTTPSURL(url) && url.path.hasSuffix("/manifest.json")
        }) else {
            manifestStorageError = "Every provider must be an HTTPS URL ending in /manifest.json."
            return
        }
        var seen = Set<String>()
        stremioAddonManifestURLs = lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        let configuration = stremioAddonManifestURLs
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try StremioAddonConfigurationStore.save(configuration)
                }.value
                guard !Task.isCancelled else { return }
                manifestStorageError = nil
                await searchStremioAddonSources()
            } catch { manifestStorageError = "The provider configuration could not be saved in Keychain." }
        }
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
        guard item.kind == .series else { return }
        let settings = try? await SourceSecureSettingsLoader.shared.load()
        guard !Task.isCancelled else { return }
        guard item.metadataProvider == "tmdb",
              let token = (settings?.tmdbToken ?? sourceSearchTMDBToken)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            episodeErrorMessage = item.metadataProvider == "tmdb"
                ? "Connect TMDB in Settings to load episode details. You can also choose an episode manually."
                : "Episode details are unavailable for this title. Choose the season and episode manually."
            return
        }

        episodeErrorMessage = nil

        do {
            let provider = TMDBCatalogProvider(readAccessToken: token)
            guard let details = try await provider.fetchDetails(for: item) else {
                episodeErrorMessage = "TMDB details are unavailable for this title."
                return
            }
            if item.kind == .series {
                seasons = details.seasonSummaries
                if !seasons.contains(where: { $0.seasonNumber == seasonNumber }), let firstSeason = seasons.first {
                    seasonNumber = firstSeason.seasonNumber
                }
                await loadEpisodes(for: seasonNumber, provider: provider, token: token)
            }
        } catch is CancellationError {
            return
        } catch {
            episodeErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadEpisodes(for requestedSeason: Int, provider existingProvider: TMDBCatalogProvider? = nil, token existingToken: String? = nil) async {
        guard item.kind == .series else { return }
        guard let token = (existingToken ?? sourceSearchTMDBToken)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            episodeErrorMessage = "Connect TMDB in Settings to load episode details."
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
    private func loadStoredManifestConfiguration() async {
        loadingProviderSettings = true
        defer { loadingProviderSettings = false }
        do {
            let settings = try await SourceSecureSettingsLoader.shared.load()
            try Task.checkCancellation()
            sourceSearchTMDBToken = settings.tmdbToken
            let normalized = settings.manifestText?.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
            if let normalized, !normalized.isEmpty, !Self.legacyDefaultStremioAddonManifestURLTexts.contains(normalized) {
                stremioAddonManifestURLs = normalized
            } else { stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText }
            manifestStorageError = settings.manifestStorageUnavailable
                ? "Saved provider settings could not be read. Built-in providers remain available." : nil
            // Do not rewrite Keychain on every source-screen appearance. Explicit provider edits
            // still persist in saveProviderConfiguration; legacy migration happens in the store.
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            manifestStorageError = error.localizedDescription
        }
    }

    private var sourceFilterRequest: SourceFilterRequest {
        SourceFilterRequest(streams: discoveredTorrentDescriptors,
                            provider: selectedTorrentProvider == "All providers" ? nil : selectedTorrentProvider,
                            quality: selectedQuality == "Any quality" ? nil : selectedQuality,
                            sort: releaseSort, query: releaseQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                            minimumSeeders: minimumSeeders, maximumBytes: smartMaximumSizeGB * 1_000_000_000,
                            hideKnownDead: hideKnownDeadReleases)
    }

    @MainActor
    private func cancelSourceSearch() {
        if searchingAddonSources { PlaybackDiagnostics.record("discovery.cancel", details: ["reason": "user_or_screen_closed"]) }
        sourceSearchGeneration = UUID()
        sourceSearchTask?.cancel()
        sourceSearchTask = nil
        searchingAddonSources = false
        sourceSearchCancelled = true
        addonSearchMessage = "Search cancelled. Releases already found remain available."
    }

    @MainActor
    private func searchStremioAddonSources(forceRefresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        let entryGeneration = UUID()
        sourceSearchGeneration = entryGeneration
        sourceSearchTask?.cancel()
        if forceRefresh {
            await loadStoredManifestConfiguration()
            guard !Task.isCancelled, sourceSearchGeneration == entryGeneration else { return }
            await SourceDiscoveryCache.shared.clearPlaybackResponses()
        }
        guard !Task.isCancelled, sourceSearchGeneration == entryGeneration, activePlaybackSheet == nil else { return }
        let task = Task { await performSourceSearch() }
        sourceSearchTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @MainActor
    private func performSourceSearch() async {
        // Reappearing beneath a player must not tear down its active torrent session.
        guard !Task.isCancelled, activePlaybackSheet == nil, torrentPreparationTask == nil else { return }
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
        let generation = UUID()
        sourceSearchGeneration = generation
        guard !Task.isCancelled, sourceSearchGeneration == generation else { return }
        searchingAddonSources = true
        sourceSearchCancelled = false
        discoveryCompletedProviders = 0
        discoveryStartedAt = Date()
        discoveryStage = "Resolving title and contacting providers…"
        releaseFailures = [:]
        providerStatuses = []
        addonSearchMessage = nil
        torrentPreparationMessage = nil
        discoveredSources = []
        discoveredTorrentDescriptors = []
        defer {
            if sourceSearchGeneration == generation {
                searchingAddonSources = false
            }
        }

        let resolver = AutomaticExternalIDResolver(tmdbReadAccessToken: sourceSearchTMDBToken)
        var addonManifestURLs = manifestURLs.filter {
            !($0.host?.lowercased().contains("torrentio") ?? false)
        }
        addonManifestURLs = MediaFusionEndpointPolicy.withFallbacks(addonManifestURLs)
        PlaybackDiagnostics.record("discovery.begin", details: [
            "addon_hosts": addonManifestURLs.compactMap(\.host).joined(separator: ","),
            "media_kind": request.mediaKind.rawValue,
            "season": request.seasonNumber.map(String.init) ?? "none",
            "episode": request.episodeNumber.map(String.init) ?? "none"
        ])
        let searchRequest = request
        let torrentioSearch = SceneBoxTorrentSearch(sourceBases: manifestURLs.filter {
            $0.host?.lowercased().contains("torrentio") ?? false
        }.map { $0.deletingLastPathComponent().absoluteString } + ["https://torrentio.strem.fun"])
        let addonURLs = addonManifestURLs
        discoveryExpectedProviders = addonURLs.count + 1
        let updates = AsyncStream<StremioAddonDiscovery>.makeStream()
        let producer = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let result = await torrentioSearch.discover(for: searchRequest, externalIDResolver: resolver)
                    updates.continuation.yield(result)
                }
                group.addTask {
                    _ = await Self.discoverAddonSources(manifestURLs: addonURLs, request: searchRequest, resolver: resolver,
                        onUpdate: { batch in updates.continuation.yield(batch) })
                }
            }
            updates.continuation.finish()
        }
        var batches: [StremioAddonDiscovery] = []
        await withTaskCancellationHandler {
            for await batch in updates.stream {
                guard !Task.isCancelled, sourceSearchGeneration == generation else { producer.cancel(); break }
                batches.append(batch)
                var seenStatuses = Set<String>()
                providerStatuses = batches.flatMap(\.providerStatuses).filter { seenStatuses.insert($0.id).inserted }
                discoveryCompletedProviders = providerStatuses.count
                discoveryStage = "\(batch.providerStatuses.map(\.name).joined(separator: ", ")) replied. Checking remaining providers…"
                var seen = Set<String>()
                discoveredSources = batches.flatMap(\.sources).filter { seen.insert($0.id).inserted }
                var seenTorrents = Set<String>()
                discoveredTorrentDescriptors = batches.flatMap(\.torrentDescriptors).filter { seenTorrents.insert($0.id).inserted }
                if discoveredTorrentDescriptors.count + discoveredSources.count > 0 {
                    addonSearchMessage = "Results are ready. You can play while other providers finish."
                }
                PlaybackDiagnostics.record("discovery.provider.ready", details: [
                    "provider": batch.providerStatuses.map(\.name).joined(separator: ","),
                    "elapsed_ms": String(Int(Date().timeIntervalSince(discoveryStartedAt) * 1_000)),
                    "torrent_count": String(discoveredTorrentDescriptors.count)])
            }
            await producer.value
        } onCancel: {
            producer.cancel()
            updates.continuation.finish()
        }
        guard !Task.isCancelled, sourceSearchGeneration == generation else { return }
        if selectedTorrentProvider != "All providers",
           !discoveredTorrentDescriptors.contains(where: { $0.providerName == selectedTorrentProvider }) {
            selectedTorrentProvider = "All providers"
        }
        PlaybackDiagnostics.record("discovery.received", details: ["torrent_count": String(discoveredTorrentDescriptors.count)])
        let statuses = batches.flatMap(\.providerStatuses)
        providerStatuses = statuses
        if !discoveredSources.isEmpty, !discoveredTorrentDescriptors.isEmpty {
            addonSearchMessage = "Found \(discoveredSources.count) direct source(s) and \(discoveredTorrentDescriptors.count) torrent option(s). Torrent transfers start only when you select one."
        } else if !discoveredSources.isEmpty {
            addonSearchMessage = "Found \(discoveredSources.count) direct source(s). Unavailable sources can be skipped."
        } else if !discoveredTorrentDescriptors.isEmpty {
            addonSearchMessage = "Found \(discoveredTorrentDescriptors.count) torrent option(s). Select one to prepare playback."
        } else {
            addonSearchMessage = "No playable sources were returned. Check the provider status below or try another source instance."
        }
        if discoveredSources.isEmpty, !discoveredTorrentDescriptors.isEmpty {
            addonSearchMessage = (addonSearchMessage ?? "") + " Direct links are optional; these add-ons returned torrent streams."
        }
        for status in statuses {
            PlaybackDiagnostics.record("discovery.provider.result", details: ["provider": status.name, "outcome": status.outcome.summary])
        }
        let displayedCounts = Dictionary(grouping: discoveredTorrentDescriptors, by: \.providerName)
            .map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: ",")
        PlaybackDiagnostics.record("discovery.display", details: ["torrents_by_provider": displayedCounts, "direct_count": String(discoveredSources.count)])
        let providerSummary = statuses.map(\.summary).joined(separator: "\n")
        if !providerSummary.isEmpty {
            addonSearchMessage = [addonSearchMessage, providerSummary].compactMap { $0 }.joined(separator: "\n")
        }
    }

    nonisolated private static func discoverAddonSources(
        manifestURLs: [URL],
        request: PlaybackSourceRequest,
        resolver: AutomaticExternalIDResolver,
        onUpdate: (@Sendable (StremioAddonDiscovery) async -> Void)? = nil
    ) async -> StremioAddonDiscovery {
        guard !manifestURLs.isEmpty else {
            return StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: [])
        }
        do {
            let provider = try StremioAddonPlaybackProvider(
                manifestURLs: manifestURLs,
                externalIDResolver: resolver
            )
            return try await provider.discover(for: request, onUpdate: onUpdate)
        } catch is CancellationError {
            return StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: [])
        } catch {
            let statuses = manifestURLs.enumerated().map { index, url in
                let host = (url.host ?? "External add-on").lowercased()
                let name = host.contains("mediafusion") ? "MediaFusion" : host
                return StremioAddonProviderStatus(
                    id: "addon-error-\(index)-\(host)",
                    name: name,
                    outcome: .failed(error.localizedDescription)
                )
            }
            let result = StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: statuses)
            if let onUpdate { await onUpdate(result) }
            return result
        }
    }

    @MainActor
    private func startTorrentPlayback(for descriptor: StremioTorrentDescriptor) {
        guard torrentPreparationTask == nil else { return }
        guard StremioTorrentDescriptor(
            infoHash: descriptor.infoHash,
            fileIndex: descriptor.fileIndex,
            trackers: descriptor.trackers,
            title: descriptor.title,
            providerName: descriptor.providerName
        ) != nil else {
            torrentPreparationMessage = "This torrent result is malformed. Choose another source."
            return
        }
        PlaybackDiagnostics.beginAttempt(provider: descriptor.providerName, fileIndex: descriptor.fileIndex)
        preparingTorrentDescriptorID = descriptor.id
        cancellingPreparation = false
        preparingTorrentTransfer = true
        torrentPreparationStartedAt = Date()
        torrentPreparationMessage = "Preparing torrent stream. Torrent metadata may take a moment to load."
        let preparationID = UUID()
        torrentPreparationGeneration = preparationID
        torrentPreparationTask = Task {
            await prepareTorrentPlayback(for: descriptor, preparationID: preparationID)
        }
    }

    @MainActor
    private func prepareTorrentPlayback(for descriptor: StremioTorrentDescriptor, preparationID: UUID) async {
        await prepareCandidates([.torrent(descriptor)], maximumAttempts: 1, preparationID: preparationID)
    }

    @MainActor
    private func prepareCandidates(_ candidates: [SmartPlaybackCandidate], maximumAttempts: Int, preparationID: UUID) async {
        let playbackRequest = request
        defer {
            if torrentPreparationGeneration == preparationID {
                preparingTorrentDescriptorID = nil
                torrentPreparationTask = nil
                smartAttemptLabel = nil
            }
        }
        do {
            let source = try await SmartPlaybackSelection.firstReady(candidates: candidates, maximumAttempts: maximumAttempts,
                onAttempt: { candidate, index, total in
                    guard torrentPreparationGeneration == preparationID else { return }
                    smartAttemptLabel = "Checking release \(index) of \(total)"
                    if case .torrent = candidate { preparingTorrentTransfer = true }
                    else { preparingTorrentTransfer = false }
                    if case .torrent(let descriptor) = candidate {
                        preparingTorrentDescriptorID = descriptor.id
                        PlaybackDiagnostics.beginAttempt(provider: descriptor.providerName, fileIndex: descriptor.fileIndex)
                    }
                    torrentPreparationMessage = "Connecting to \(candidate.title)…"
                }, onFailure: { candidate, message in
                    guard torrentPreparationGeneration == preparationID else { return }
                    if case .torrent(let descriptor) = candidate { releaseFailures[descriptor.id] = message }
                    else { releaseFailures[candidate.id] = message }
                    torrentPreparationMessage = message
                    PlaybackDiagnostics.record("playback.selection.failed", details: ["provider": candidate.title])
                }, discard: { source in
                    _ = await TorrentPlaybackSessionRegistry.shared.stop(for: source.url)
                }, prepare: { candidate in
                    switch candidate {
                    case .direct(let source):
                        return try await DirectPlaybackReadinessProbe().confirm(source)
                    case .torrent(let descriptor):
                        let engine = XITRIXTorrentPlaybackEngine(descriptor: descriptor) { message in
                            Task { @MainActor in
                                guard torrentPreparationGeneration == preparationID else { return }
                                torrentPreparationMessage = message
                            }
                        }
                        let provider = TorrentPlaybackProvider(engine: engine)
                        var registeredSources: [PlaybackSource] = []
                        do {
                            let sources = try await provider.findSources(for: playbackRequest)
                            registeredSources = sources
                            try Task.checkCancellation()
                            guard torrentPreparationGeneration == preparationID else { throw CancellationError() }
                            guard let source = sources.first else { throw SmartPlaybackSelection.SelectionError.unreachableLink }
                            return source
                        } catch {
                            for source in registeredSources { _ = await TorrentPlaybackSessionRegistry.shared.stop(for: source.url) }
                            await provider.stop()
                            throw error
                        }
                    }
                })
            guard !Task.isCancelled, torrentPreparationGeneration == preparationID else {
                _ = await TorrentPlaybackSessionRegistry.shared.stop(for: source.url)
                return
            }
            activePlaybackSheet = .discovered(source)
            torrentPreparationMessage = "Startup data received. Opening player…"
        } catch is CancellationError {
            if torrentPreparationGeneration == preparationID { torrentPreparationMessage = "Preparation cancelled." }
        } catch {
            if torrentPreparationGeneration == preparationID { torrentPreparationMessage = error.localizedDescription }
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

private enum WatchPlaybackSheet: Identifiable {
    case embedded(ResolvedEmbedSource)
    case discovered(PlaybackSource)

    var id: String {
        switch self {
        case .embedded(let source):
            return "embedded:\(source.id)"
        case .discovered(let source):
            return "discovered:\(source.id)"
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
            .toolbarBackground(.hidden, for: .navigationBar)
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
    let item: MediaItem
    let seasonNumber: Int
    let episodeNumber: Int
    let onTorrentSessionStopped: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SceneBoxStreamPlaybackView(
            source: source,
            item: item,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            onClose: { dismiss() }
        )
        .onDisappear {
            Task { @MainActor in
                if await TorrentPlaybackSessionRegistry.shared.stop(for: source.url) {
                    onTorrentSessionStopped()
                }
            }
        }
    }
}

private struct SourceFilterRequest: Equatable, Sendable {
    let streams: [StremioTorrentDescriptor]
    let provider: String?
    let quality: String?
    let sort: SourceReleaseSort
    let query: String
    let minimumSeeders: Int
    let maximumBytes: Double
    let hideKnownDead: Bool
}
