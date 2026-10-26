import AVKit
import SwiftUI

struct WatchHubView: View {
    let item: MediaItem
    let onPlayDirect: (MediaItem) -> Void
    let onSelectItem: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.defaultPlaybackProvider") private var defaultProviderID = "smart"
    @State private var stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
    @State private var manifestStorageError: String?
    @State private var manifestConfigurationLoaded = false
    @State private var sourceSearchGeneration = UUID()

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
    @State private var torrentPreparationTask: Task<Void, Never>?
    @State private var torrentPreparationGeneration = UUID()
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
        return SceneBoxStreamPicker.ordered(discoveredTorrentDescriptors)
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
            .sheet(item: $activePlaybackSheet) { playbackSheet in
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
                    loadStoredManifestConfiguration()
                    manifestConfigurationLoaded = true
                }
                resolveSources()
                await searchStremioAddonSources()
            }
            .task(id: item.id) {
                await loadCatalogDetails()
            }
            .onDisappear {
                torrentPreparationTask?.cancel()
                torrentPreparationTask = nil
                torrentPreparationGeneration = UUID()
                sourceSearchGeneration = UUID()
                Task {
                    await TorrentPlaybackSessionRegistry.shared.stopAll()
                }
            }
        }
        .tint(Color.cineNexAccent)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CachedPosterImage(
                url: item.posterURL,
                fallbackSymbol: item.symbol,
                symbolSize: 94
            )
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: Color.cineNexBackground.opacity(0.35), location: 0.42),
                    .init(color: Color.cineNexBackground.opacity(0.98), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("CINENEX WATCH", systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.cineNexAccent)
                    Spacer()
                    Text(item.kind == .movie ? "MOVIE" : "SERIES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.42), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }

                Spacer(minLength: 80)

                Text(item.title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 8) {
                    if let year = item.yearLabel {
                        Text(year)
                        Text("·")
                    }
                    Text(item.genre)
                    if let rating = item.rating {
                        Text("·")
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.28))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

                Text(item.synopsis)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if availableProviders.isEmpty && discoveredSources.isEmpty && discoveredTorrentDescriptors.isEmpty && item.streamURL == nil {
                    Task { await searchStremioAddonSources() }
                } else if (defaultProviderID == "smart" || defaultProviderID == "direct"), item.streamURL != nil {
                    onPlayDirect(item)
                } else if defaultProviderID == "stremio-addons", let source = discoveredSources.first {
                    activePlaybackSheet = .discovered(source)
                } else if defaultProviderID == "libtorrent", let descriptor = discoveredTorrentDescriptors.first {
                    startTorrentPlayback(for: descriptor)
                } else if (defaultProviderID == "smart" || defaultProviderID == "direct"),
                          let source = discoveredSources.first {
                    activePlaybackSheet = .discovered(source)
                } else if (defaultProviderID == "smart" || defaultProviderID == "libtorrent"),
                          let descriptor = discoveredTorrentDescriptors.first {
                    startTorrentPlayback(for: descriptor)
                } else if let preferred = availableProviders.first(where: { $0.provider.id == defaultProviderID }) {
                    activePlaybackSheet = .embedded(preferred)
                } else if let first = discoveredSources.first {
                    activePlaybackSheet = .discovered(first)
                } else if let descriptor = discoveredTorrentDescriptors.first {
                    startTorrentPlayback(for: descriptor)
                } else if let first = availableProviders.first {
                    activePlaybackSheet = .embedded(first)
                } else if item.streamURL != nil {
                    onPlayDirect(item)
                } else {
                    Task { await searchStremioAddonSources() }
                }
            } label: {
                let hasSource = item.streamURL != nil || !availableProviders.isEmpty || !discoveredSources.isEmpty || !discoveredTorrentDescriptors.isEmpty
                Label(
                    searchingAddonSources ? "Searching sources…" : (item.streamURL != nil ? "Play now" : (hasSource ? "Quick Play" : "Find sources")),
                    systemImage: searchingAddonSources ? "hourglass" : (hasSource ? "play.fill" : "dot.radiowaves.left.and.right")
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchingAddonSources || preparingTorrentDescriptorID != nil)
            .accessibilityHint("Starts playback when a source is available, or searches the built-in add-ons if none have been found")

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
                    Text("Available sources")
                        .font(.title3.bold())
                    Text("Direct streams and torrents come from add-ons. Embedded websites open third-party players and may fail for individual titles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(discoveredSources.count + (item.streamURL == nil ? 0 : 1)) direct · \(discoveredTorrentDescriptors.count) torrent · \(availableProviders.count) embedded")
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
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
                        Text(searchingAddonSources ? "Searching all sources…" : "Find more sources")
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

                Picker("Source type", selection: $selectedSourceFilter) {
                    ForEach(["All", "Direct", "Torrent", "Web"], id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Filter playback sources by type")

                Text("Tap a source to test it. Direct links, torrent streams, and experimental web players are shown separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup {
                    HStack(spacing: 14) {
                        Link("Configure Torrentio", destination: URL(string: "https://torrentio.strem.fun/configure")!)
                        Link("Configure MediaFusion", destination: URL(string: "https://mediafusion.elfhosted.com/")!)
                        Spacer(minLength: 0)
                        Button("Restore defaults") {
                            stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
                        }
                        .font(.caption.weight(.medium))
                    }
                    .font(.caption.weight(.medium))
                    Text("Advanced: one HTTPS manifest URL per line. Custom add-on URLs stay in the iOS Keychain on this device.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $stremioAddonManifestURLs)
                        .font(.caption.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 76, maxHeight: 120)
                        .padding(8)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Stremio add-on manifest URLs")
                        .privacySensitive()
                        .onAppear {
                            do {
                                let storedManifestURLs = try StremioAddonConfigurationStore.load()
                                let normalizedManifestURLs = storedManifestURLs?
                                    .split(whereSeparator: \.isNewline)
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .joined(separator: "\n")
                                if let normalizedManifestURLs,
                                   !normalizedManifestURLs.isEmpty,
                                   !Self.legacyDefaultStremioAddonManifestURLTexts.contains(normalizedManifestURLs) {
                                    stremioAddonManifestURLs = normalizedManifestURLs
                                } else {
                                    stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
                                }
                                try StremioAddonConfigurationStore.save(stremioAddonManifestURLs)
                                manifestStorageError = nil
                            } catch {
                                manifestStorageError = "Secure storage is unavailable. Your add-on URLs could not be saved to the iOS Keychain."
                            }
                        }
                        .onChange(of: stremioAddonManifestURLs) { _, newValue in
                            do {
                                try StremioAddonConfigurationStore.save(newValue)
                                manifestStorageError = nil
                            } catch {
                                manifestStorageError = "Secure storage is unavailable. Your add-on URL changes could not be saved to the iOS Keychain."
                            }
                        }
    
                } label: {
                    Label("Advanced provider settings", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Color.cineNexAccent)
                if let manifestStorageError {
                    Label(manifestStorageError, systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let addonSearchMessage {
                    Text(addonSearchMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !visibleDirectSources.isEmpty {
                    Label("Direct stream links", systemImage: "play.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
                ForEach(visibleDirectSources) { source in
                    Button {
                        activePlaybackSheet = .discovered(source)
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
                
                if !visibleTorrentSources.isEmpty {
                    let providerNames = Array(Set(visibleTorrentSources.map(\.providerName))).sorted()
                    Label("Torrent sources · \(providerNames.joined(separator: " · "))", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
                ForEach(visibleTorrentSources) { descriptor in
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
                                Text(descriptor.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text([
                                    descriptor.providerName,
                                    SceneBoxStreamPicker.resolution(for: descriptor),
                                    SceneBoxStreamPicker.seeders(for: descriptor).map { "\($0) seeders" },
                                    SceneBoxStreamPicker.size(for: descriptor),
                                    descriptor.fileIndex.map { "File index \($0)" }
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
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

            if showsDirectPlayback && item.streamURL != nil {
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

            if !hasVisibleSources && !searchingAddonSources {
                ContentUnavailableView(
                    "No compatible sources found",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(request.tmdbID == nil
                        ? "No verified direct source is attached. Configure a compatible Stremio add-on or provide a direct media URL."
                        : "No direct source was found. Check your Stremio add-ons or try another provider.")
                )
                .padding(.vertical, 8)
            }

            if !visibleEmbeddedSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Embedded websites", systemImage: "globe")
                        .font(.subheadline.weight(.semibold))
                    Text("These are fallback web players, not verified direct streams. If one fails, return here and try another.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                ForEach(visibleEmbeddedSources) { source in
                    Button {
                        activePlaybackSheet = .embedded(source)
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
    private func loadStoredManifestConfiguration() {
        do {
            let storedManifestURLs = try StremioAddonConfigurationStore.load()
            let normalizedManifestURLs = storedManifestURLs?
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n")
            if let normalizedManifestURLs,
               !normalizedManifestURLs.isEmpty,
               !Self.legacyDefaultStremioAddonManifestURLTexts.contains(normalizedManifestURLs) {
                stremioAddonManifestURLs = normalizedManifestURLs
            } else {
                stremioAddonManifestURLs = Self.defaultStremioAddonManifestURLText
            }
            try StremioAddonConfigurationStore.save(stremioAddonManifestURLs)
            manifestStorageError = nil
        } catch {
            manifestStorageError = "Secure storage is unavailable. Your add-on URLs could not be saved to the iOS Keychain."
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
        let generation = UUID()
        sourceSearchGeneration = generation
        await TorrentPlaybackSessionRegistry.shared.stopAll()
        guard !Task.isCancelled, sourceSearchGeneration == generation else { return }
        searchingAddonSources = true
        addonSearchMessage = nil
        torrentPreparationMessage = nil
        discoveredSources = []
        discoveredTorrentDescriptors = []
        defer {
            if sourceSearchGeneration == generation {
                searchingAddonSources = false
            }
        }

        let resolver = AutomaticExternalIDResolver(tmdbReadAccessToken: TMDBTokenStore.load())
        let addonManifestURLs = manifestURLs.filter {
            !($0.host?.lowercased().contains("torrentio") ?? false)
        }
        async let torrentioResult = SceneBoxTorrentSearch().discover(
            for: request,
            externalIDResolver: resolver
        )
        async let addonResult = Self.discoverAddonSources(
            manifestURLs: addonManifestURLs,
            request: request,
            resolver: resolver
        )
        let (torrentioDiscovery, addonDiscovery) = await (torrentioResult, addonResult)
        guard !Task.isCancelled, sourceSearchGeneration == generation else { return }

        var seenSourceIDs = Set<String>()
        discoveredSources = (torrentioDiscovery.sources + addonDiscovery.sources).filter {
            seenSourceIDs.insert($0.id).inserted
        }
        var seenDescriptorIDs = Set<String>()
        discoveredTorrentDescriptors = Array(
            (torrentioDiscovery.torrentDescriptors + addonDiscovery.torrentDescriptors).filter {
                seenDescriptorIDs.insert($0.id).inserted
            }.prefix(12)
        )
        let statuses = torrentioDiscovery.providerStatuses + addonDiscovery.providerStatuses
        if !discoveredSources.isEmpty, !discoveredTorrentDescriptors.isEmpty {
            addonSearchMessage = "Found \(discoveredSources.count) direct source(s) and \(discoveredTorrentDescriptors.count) torrent option(s). Torrent transfers start only when you select one."
        } else if !discoveredSources.isEmpty {
            addonSearchMessage = "Found \(discoveredSources.count) direct source(s). VLC will attempt playback; unavailable sources can be skipped."
        } else if !discoveredTorrentDescriptors.isEmpty {
            addonSearchMessage = "Found \(discoveredTorrentDescriptors.count) torrent option(s). Select one to prepare playback."
        } else {
            addonSearchMessage = "No playable sources were returned. Check the provider status below or try another source instance."
        }
        let providerSummary = statuses.map(\.summary).joined(separator: "\n")
        if !providerSummary.isEmpty {
            addonSearchMessage = [addonSearchMessage, providerSummary].joined(separator: "\n")
        }
    }

    private static func discoverAddonSources(
        manifestURLs: [URL],
        request: PlaybackSourceRequest,
        resolver: AutomaticExternalIDResolver
    ) async -> StremioAddonDiscovery {
        guard !manifestURLs.isEmpty else {
            return StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: [])
        }
        do {
            let provider = try StremioAddonPlaybackProvider(
                manifestURLs: manifestURLs,
                externalIDResolver: resolver
            )
            return try await provider.discover(for: request)
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
            return StremioAddonDiscovery(sources: [], torrentDescriptors: [], providerStatuses: statuses)
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
        preparingTorrentDescriptorID = descriptor.id
        torrentPreparationMessage = "Preparing native playback. Torrent metadata may take a moment to load."
        let preparationID = UUID()
        torrentPreparationGeneration = preparationID
        torrentPreparationTask = Task {
            await prepareTorrentPlayback(for: descriptor, preparationID: preparationID)
        }
    }

    @MainActor
    private func prepareTorrentPlayback(for descriptor: StremioTorrentDescriptor, preparationID: UUID) async {
        let engine = XITRIXTorrentPlaybackEngine(descriptor: descriptor)
        let provider = TorrentPlaybackProvider(engine: engine)
        defer {
            if torrentPreparationGeneration == preparationID {
                if preparingTorrentDescriptorID == descriptor.id {
                    preparingTorrentDescriptorID = nil
                }
                torrentPreparationTask = nil
            }
        }

        do {
            let sources = try await provider.findSources(for: request)
            try Task.checkCancellation()
            guard torrentPreparationGeneration == preparationID else {
                await provider.stop()
                return
            }
            guard let source = sources.first else {
                await provider.stop()
                torrentPreparationMessage = "This torrent did not contain a playable file supported by CineNex."
                return
            }
            activePlaybackSheet = .discovered(source)
            torrentPreparationMessage = "Torrent source is ready. Opening the native player."
        } catch is CancellationError {
            await provider.stop()
            if torrentPreparationGeneration == preparationID {
                torrentPreparationMessage = "Torrent preparation was cancelled."
            }
        } catch {
            await provider.stop()
            if torrentPreparationGeneration == preparationID {
                torrentPreparationMessage = "Native torrent playback failed: \(error.localizedDescription). Try another source."
            }
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
