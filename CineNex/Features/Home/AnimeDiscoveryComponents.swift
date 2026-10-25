import SwiftUI

struct AnimeFeaturedBanner: View {
    let anime: AnimeTitle
    let onDetails: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedPosterImage(
                url: anime.coverURL,
                fallbackSymbol: "sparkles.tv",
                symbolSize: 94
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.04), location: 0),
                    .init(color: Color.cineNexBackground.opacity(0.48), location: 0.36),
                    .init(color: Color.cineNexBackground.opacity(0.99), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.cineNexAccent.opacity(0.24), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 11) {
                Label("TRENDING ANIME", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.cineNexAccent)
                Text(anime.title)
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                HStack(spacing: 7) {
                    if let year = anime.seasonYear {
                        Text(String(year))
                        Text("·")
                    }
                    Text(anime.format?.replacingOccurrences(of: "_", with: " ") ?? "ANIME")
                    if let episodes = anime.episodeCount {
                        Text("·")
                        Text("\(episodes) ep")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.84))
                if let rating = anime.averageRating {
                    Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                }
                Button(action: onDetails) {
                    Label("Anime details", systemImage: "info.circle")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.cineNexAccent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(22)
        }
        .frame(height: 355)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }
}

struct AnimePosterCard: View {
    let anime: AnimeTitle
    let watchedEpisodes: Int
    let action: () -> Void

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
                        fallbackSymbol: "sparkles.tv",
                        symbolSize: 38
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    if let rating = anime.averageRating {
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

struct AnimeDetailView: View {
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
                            fallbackSymbol: "sparkles.tv",
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

                    if !anime.genres.isEmpty {
                        Text(anime.genres.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.cineNexAccent)
                    }

                    if !anime.synopsis.isEmpty {
                        Text(anime.synopsis)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Episode progress")
                            .font(.title3.bold())
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
                        Button("Reset episode progress", role: .destructive) {
                            progressStore.resetProgress(for: anime.id)
                        }
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
            .navigationTitle("Anime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.cineNexAccent)
        .preferredColorScheme(.dark)
    }

    private var metadataLine: String {
        [
            anime.seasonYear.map(String.init),
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
