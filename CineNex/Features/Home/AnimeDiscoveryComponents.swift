import SwiftUI

struct AnimeFeaturedBanner: View {
    let anime: AnimeTitle
    let onDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            CachedPosterImage(url: anime.coverURL, fallbackSymbol: "sparkles", symbolSize: 44)
                .frame(width: 116, height: 174)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                Text("ANIME SPOTLIGHT").font(.caption2.weight(.bold)).tracking(2)
                    .foregroundStyle(Color.cineNexAccent)
                Text(anime.title).font(.title2.bold()).lineLimit(3)
                Text([anime.seasonYear.map(String.init), anime.format?.replacingOccurrences(of: "_", with: " ")]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Button(action: onDetails) {
                    Label("Explore series", systemImage: "arrow.up.right")
                        .font(.subheadline.bold()).padding(.vertical, 11).padding(.horizontal, 14)
                        .foregroundStyle(.white).background(Color.cineNexAccent, in: Capsule())
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.07)) }
        .padding(.horizontal, 20)
    }
}

struct AnimePosterCard: View {
    let anime: AnimeTitle
    let watchedEpisodes: Int
    let action: () -> Void
    @AppStorage("cinenex.showRatings") private var showRatings = true

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            LinearGradient(
                                colors: [Color.cineNexAccent.opacity(0.4), Color.cineNexSurface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    CachedPosterImage(
                        url: anime.coverURL,
                        fallbackSymbol: "sparkles",
                        symbolSize: 38
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    if showRatings, let rating = anime.averageRating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(8)
                    }
                }
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 15))

                Text(anime.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    if let year = anime.seasonYear {
                        Text(String(year))
                    }
                    if let episodes = anime.episodeCount {
                        if anime.seasonYear != nil { Text("·") }
                        Text("\(episodes) eps")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if watchedEpisodes > 0 {
                    if let total = anime.episodeCount, total > 0 {
                        ProgressView(value: min(Double(watchedEpisodes) / Double(total), 1))
                            .tint(Color.cineNexAccent)
                        Text("\(min(watchedEpisodes, total)) of \(total) watched")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(watchedEpisodes) episodes watched")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens anime details and episode tracking")
    }
}

struct AnimePosterShelf: View {
    let items: [AnimeTitle]
    let progressStore: AnimeProgressStore
    let onSelect: (AnimeTitle) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(items) { anime in
                    AnimePosterCard(
                        anime: anime,
                        watchedEpisodes: progressStore.watchedEpisodeCount(for: anime)
                    ) {
                        onSelect(anime)
                    }
                    .frame(width: 152)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Trending anime")
    }
}

struct AnimeDetailView: View {
    @State private var selectedWatchProvider: AnimeWebsiteProvider?
    @State private var synopsisExpanded = false
    @State private var confirmingReset = false
    let anime: AnimeTitle
    @ObservedObject var progressStore: AnimeProgressStore
    @Environment(\.dismiss) private var dismiss

    private var watchedEpisodes: Int {
        progressStore.watchedEpisodeCount(for: anime)
    }

    private var episodeRange: ClosedRange<Int> {
        0...max(0, anime.episodeCount ?? 9_999)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        CachedPosterImage(
                            url: anime.coverURL,
                            fallbackSymbol: "sparkles",
                            symbolSize: 44
                        )
                        .frame(width: 126, height: 178)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 9) {
                            Text(anime.title)
                                .font(.title2.bold())
                            if let nativeTitle = anime.nativeTitle, !nativeTitle.isEmpty {
                                Text(nativeTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let rating = anime.averageRating {
                                Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                            }
                            Text(metadataLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let myAnimeListID = anime.myAnimeListID,
                       let myAnimeListURL = URL(string: "https://myanimelist.net/anime/\(myAnimeListID)") {
                        Link(destination: myAnimeListURL) {
                            Label("View on MyAnimeList", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.cineNexSurface, in: Capsule())
                        }
                        .accessibilityHint("Opens this anime's MyAnimeList entry")
                    }

                    if !anime.genres.isEmpty {
                        Text(anime.genres.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.cineNexAccent)
                    }

                    if !anime.synopsis.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("The story").font(.title3.bold())
                            Text(anime.synopsis).font(.body).foregroundStyle(.secondary)
                                .lineLimit(synopsisExpanded ? nil : 5)
                            if anime.synopsis.count > 220 {
                                Button(synopsisExpanded ? "Read less" : "Read full story") { synopsisExpanded.toggle() }
                                    .font(.caption.bold())
                            }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 24))
                    }

                    AnimeWatchProviderSection(anime: anime) { provider in
                        selectedWatchProvider = provider
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("YOUR EPISODES", systemImage: "checkmark.circle")
                            .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Color.cineNexAccent)
                        Text(progressSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Stepper(
                            "Episodes watched: \(watchedEpisodes)",
                            value: Binding(
                                get: { progressStore.watchedEpisodeCount(for: anime) },
                                set: { progressStore.setWatchedEpisodeCount($0, for: anime) }
                            ),
                            in: episodeRange
                        )
                        .font(.subheadline)
                        if let total = anime.episodeCount, total > 0 {
                            ProgressView(value: min(Double(watchedEpisodes) / Double(total), 1))
                                .tint(Color.cineNexAccent)
                        }
                        Button {
                            progressStore.setWatchedEpisodeCount(min(watchedEpisodes + 1, episodeRange.upperBound), for: anime)
                        } label: {
                            Label("Mark next episode watched", systemImage: "checkmark")
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                        }.buttonStyle(.borderedProminent)
                            .disabled(watchedEpisodes >= episodeRange.upperBound)
                        Button("Reset episode progress", role: .destructive) { confirmingReset = true }
                        .disabled(watchedEpisodes == 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))

                    Text("Anime metadata is provided by AniList. Episode tracking is saved on this device; playback availability depends on compatible providers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color.cineNexBackground.ignoresSafeArea())
            .navigationTitle("Anime studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset watched episodes?", isPresented: $confirmingReset) {
                Button("Reset episode progress", role: .destructive) { progressStore.resetProgress(for: anime.id) }
            } message: { Text("This removes the local episode count for this anime.") }
            .sheet(item: $selectedWatchProvider) { provider in
                AnimeWebsitePlaybackSheet(anime: anime, provider: provider)
            }
        }
        .tint(Color.cineNexAccent)
        .preferredColorScheme(.dark)
    }

    private var metadataLine: String {
        [
            anime.seasonYear.map { String($0) },
            anime.format?.replacingOccurrences(of: "_", with: " "),
            anime.status?.replacingOccurrences(of: "_", with: " "),
            anime.episodeCount.map { "\($0) episodes" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var progressSummary: String {
        if let total = anime.episodeCount {
            return "\(min(watchedEpisodes, total)) of \(total) episodes watched"
        }
        return "\(watchedEpisodes) episodes watched"
    }
}
