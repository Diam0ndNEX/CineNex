import SwiftUI

struct WatchHubView: View {
    let item: MediaItem
    let onPlayDirect: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.defaultPlaybackProvider") private var defaultProviderID = "smart"
    @State private var selectedProvider: EmbedPlaybackProvider?
    @State private var showingPlayer = false
    @State private var availableProviders: [ResolvedEmbedSource] = []

    private var request: PlaybackSourceRequest {
        PlaybackSourceRequest(
            title: item.title,
            mediaKind: item.kind == .movie ? .movie : .series,
            tmdbID: item.metadataProvider == "tmdb" ? item.externalID : nil,
            releaseYear: item.year > 0 ? item.year : nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    quickActions
                    providerSection
                    recommendationsPlaceholder
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
                if let preferred = availableProviders.first(where: { $0.provider.id == defaultProviderID }) {
                    selectedProvider = preferred
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
            .disabled(availableProviders.isEmpty && item.streamURL == nil)
            .accessibilityHint("Starts the preferred available playback source")

            Picker("Default source", selection: $defaultProviderID) {
                Text("Smart Default").tag("smart")
                ForEach(availableProviders) { source in
                    Text(source.provider.displayName).tag(source.provider.id)
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
                    Text("Choose a source or set your default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(availableProviders.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cineNexSurface, in: Capsule())
            }

            if availableProviders.isEmpty {
                ContentUnavailableView(
                    "No embed sources available",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(request.tmdbID == nil
                        ? "This title needs a verified TMDB identifier before compatible sources can be requested."
                        : "No configured source could create a valid embed URL for this title. Try a title from the live TMDB catalog.")
                )
                .padding(.vertical, 8)
            } else {
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
                                    if source.provider.id == defaultProviderID || (defaultProviderID == "smart" && source == availableProviders.first) {
                                        Text("DEFAULT")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color.cineNexAccent)
                                    }
                                }
                                Text("Web player · opens in CineNex")
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
                }
            }
        }
    }

    private var recommendationsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep discovering")
                .font(.title3.bold())
            Text("Recommendations from TMDB will stay available here as the Watch Hub grows. Source availability is checked separately from catalog metadata.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
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

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    ContentUnavailableView {
                        Label("Player couldn't load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("This source may be unavailable or incompatible with iOS. Return to the source list and try another provider.")
                    } actions: {
                        Button("Try Again") { loadFailed = false }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    EmbedWebView(url: url, onFailure: { loadFailed = true })
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
