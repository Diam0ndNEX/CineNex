import SwiftUI

/// Reuses SceneBox's poster shelves and searchable collection flow with CineNex metadata.
struct CatalogPosterTile: View {
    let item: MediaItem
    @AppStorage("cinenex.showRatings") private var showRatings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 34)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .background(Color.cineNexSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Text(item.yearLabel ?? item.kind.rawValue)
                if showRatings, let rating = item.rating, rating > 0 {
                    Text("·")
                    Image(systemName: "star.fill").font(.system(size: 9))
                    Text(String(format: "%.1f", rating))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct CatalogFeatureCard: View {
    let item: MediaItem
    let saved: Bool
    let onDetails: () -> Void
    let onPlay: () -> Void
    let onSave: () -> Void
    @AppStorage("cinenex.showRatings") private var showRatings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("ON YOUR RADAR", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .heavy)).tracking(2)
                    .foregroundStyle(Color.cineNexAccent)
                Spacer()
                Text(item.kind.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                Button(action: onDetails) {
                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 32)
                        .frame(width: 104, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .rotationEffect(.degrees(-3))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                }.accessibilityLabel("Details for \(item.title)")
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: onDetails) {
                        Text(item.title).font(.system(size: 26, weight: .heavy, design: .rounded))
                            .tracking(-0.6).foregroundStyle(.primary).lineLimit(3).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 8) {
                        if let year = item.yearLabel { Text(year) }
                        if showRatings, let rating = item.rating, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(.yellow)
                        }
                    }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(item.genre).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(item.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button(action: onPlay) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Watch now")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(15)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color.cineNexBackground)
                }
                Button(action: onSave) {
                    Image(systemName: saved ? "checkmark" : "plus")
                        .font(.headline).frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityLabel(saved ? "Remove from watchlist" : "Add to watchlist")
            }
        }
        .buttonStyle(.plain)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 312, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Color.cineNexAccent.opacity(0.18), Color.cineNexSurface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct CatalogLibraryRow: View {
    let item: MediaItem
    var progress: PlaybackProgress? = nil
    let onDetails: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onDetails) {
                HStack(alignment: .top, spacing: 14) {
                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 25)
                        .frame(width: 70, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Text([item.yearLabel, item.kind.rawValue].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let progress {
                            ProgressView(value: progress.completionFraction ?? 0).tint(Color.cineNexAccent)
                            Text("\(Int(progress.position / 60)) min watched")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text(item.genre).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.subheadline.bold())
                    .frame(width: 42, height: 42)
                    .background(Color.cineNexAccent.opacity(0.15), in: Circle())
                    .foregroundStyle(Color.cineNexAccent)
            }
            .accessibilityLabel(progress == nil ? "Watch \(item.title)" : "Resume \(item.title)")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
    }
}

struct CatalogBrowserView: View {
    let title: String
    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void
    var footer: AnyView? = nil
    @State private var query = ""
    @State private var sort = CatalogCollectionSort.relevance
    @State private var selectedGenre = ""
    @State private var selectedKind = "all"
    @State private var selectedYear = 0
    @AppStorage("cinenex.posterDensity") private var posterDensity = "comfortable"

    private var genres: [String] {
        Array(Set(items.flatMap { $0.genre.components(separatedBy: CharacterSet(charactersIn: ",·/")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private var results: [MediaItem] {
        let matches = items.filter { item in
            (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)) &&
            (selectedGenre.isEmpty || item.genre.localizedCaseInsensitiveContains(selectedGenre)) &&
            (selectedKind == "all" || (selectedKind == "movies" && item.kind == .movie) || (selectedKind == "series" && item.kind == .series)) &&
            (selectedYear == 0 || item.year == selectedYear)
        }
        switch sort {
        case .relevance: return matches
        case .newest: return matches.sorted { $0.year == $1.year ? $0.title < $1.title : $0.year > $1.year }
        case .rating: return matches.sorted { ($0.rating ?? 0) == ($1.rating ?? 0) ? $0.title < $1.title : ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .title: return matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker("Content type", selection: $selectedKind) {
                    Text("All").tag("all")
                    Text("Movies").tag("movies")
                    Text("Series").tag("series")
                }.pickerStyle(.segmented)
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        browseSortButton("Popular", sort: .relevance)
                        browseSortButton("Newest", sort: .newest)
                        browseSortButton("Top rated", sort: .rating)
                        browseSortButton("A–Z", sort: .title)
                    }
                }.scrollIndicators(.hidden)
                HStack {
                    Text("\(results.count) titles").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Genre", selection: $selectedGenre) {
                            Text("All genres").tag("")
                            ForEach(genres, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Release year", selection: $selectedYear) {
                            Text("All years").tag(0)
                            ForEach(Array(Set(items.map(\.year).filter { $0 > 0 })).sorted(by: >), id: \.self) { Text(String($0)).tag($0) }
                        }
                        Picker("Sort", selection: $sort) {
                            ForEach(CatalogCollectionSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label("Filter & sort", systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if !selectedGenre.isEmpty || selectedKind != "all" || selectedYear != 0 || !query.isEmpty {
                    HStack(spacing: 8) {
                        if !selectedGenre.isEmpty { Text(selectedGenre).font(.caption.weight(.semibold)) }
                        if selectedYear != 0 { Text(String(selectedYear)).font(.caption.weight(.semibold)) }
                        Spacer()
                        Button("Clear filters", systemImage: "xmark.circle") {
                            selectedGenre = ""
                            selectedKind = "all"
                            selectedYear = 0
                            query = ""
                        }.font(.caption.weight(.semibold))
                    }
                }
                if results.isEmpty {
                    ContentUnavailableView("No matching titles", systemImage: "film.stack",
                                           description: Text("Try another title or clear the genre filter."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: posterDensity == "compact" ? 104 : 140), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(results) { item in
                            Button { onSelect(item) } label: { CatalogPosterTile(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if let footer { footer }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Filter these titles")
    }
    private func browseSortButton(_ title: String, sort value: CatalogCollectionSort) -> some View {
        Button { sort = value } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 15).padding(.vertical, 10)
                .foregroundStyle(sort == value ? Color.cineNexAccent : Color.primary)
                .cineNexGlass(in: Capsule(), prominent: sort == value)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sort == value ? .isSelected : [])
    }

}

private enum CatalogCollectionSort: String, CaseIterable, Identifiable {
    case relevance = "Original order"
    case newest = "Newest first"
    case rating = "Highest rated"
    case title = "Title A–Z"
    var id: String { rawValue }
}

/// Checkpoints represent completed stages, not an estimated download percentage.
struct CatalogLoadingStatus: View {
    let title: String
    let stage: Int
    let stages: [String]

    private var clampedStage: Int { min(max(stage, 0), max(stages.count - 1, 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                ProgressView().controlSize(.small)
            }
            ProgressView(value: Double(clampedStage), total: Double(max(stages.count - 1, 1)))
                .tint(Color.cineNexAccent)
            if !stages.isEmpty {
                Text(stages[clampedStage]).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct CatalogDetailHero: View {
    let item: MediaItem
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(item.kind == .movie ? "FEATURE FILM" : "SERIES", systemImage: item.symbol)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.8)
                    .foregroundStyle(Color.cineNexAccent)
                Spacer()
                ShareLink(item: item.title) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: Circle())
                }.accessibilityLabel("Share title")
            }
            if dynamicType.isAccessibilitySize {
                poster
                metadata
            } else {
                HStack(alignment: .center, spacing: 22) {
                    poster
                    metadata
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.cineNexAccent.opacity(0.17), Color.cineNexSurface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var poster: some View {
        CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 42)
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title).font(.system(size: 29, weight: .heavy, design: .rounded))
                .tracking(-0.7).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                if let year = item.yearLabel { Text(year) }
                if showRatings, let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(.yellow)
                }
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if !item.runtime.isEmpty {
                Label(item.runtime, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
            Text(item.genre).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One request per visibility entry: adding pages never rekeys this view into an auto-fetch loop.
struct CatalogAutomaticPageFooter: View {
    let loadedCount: Int
    let isLoading: Bool
    let error: String?
    let onLoad: () -> Void
    @State private var enteredViewport = false
    @State private var requestedInEntry = false

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                Button("Retry loading titles", systemImage: "arrow.clockwise", action: onLoad)
                    .font(.subheadline.weight(.semibold)).disabled(isLoading)
            } else if isLoading {
                ProgressView("Loading more titles…")
            } else {
                Label("Keep exploring", systemImage: "arrow.down")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text("\(loadedCount) titles loaded").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding(16)
        .onAppear {
            enteredViewport = true
            requestIfEligible()
        }
        .onChange(of: isLoading) { _, loading in
            if !loading { requestIfEligible() }
        }
        .onDisappear {
            enteredViewport = false
            requestedInEntry = false
        }
    }

    private func requestIfEligible() {
        guard enteredViewport, !requestedInEntry, !isLoading, error == nil else { return }
        requestedInEntry = true
        onLoad()
    }
}
