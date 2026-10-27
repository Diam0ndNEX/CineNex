import SwiftUI

/// Reuses SceneBox's poster shelves and searchable collection flow with CineNex metadata.
struct CatalogPosterTile: View {
    let item: MediaItem
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @AppStorage("cinenex.posterMetadata") private var showMetadata = true

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
            if showMetadata {
            HStack(spacing: 6) {
                Text(item.yearLabel ?? item.kind.rawValue)
                if showRatings, let rating = item.rating, rating > 0 {
                    Text("·")
                    Image(systemName: "star.fill").font(.caption2)
                    Text(String(format: "%.1f", rating))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            }
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
    var presentationHeight: CGFloat = 440
    var fullBleed = false
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @AppStorage("cinenex.featuredStyle") private var featuredStyle = "immersive"
    @AppStorage("cinenex.featuredSynopsis") private var showSynopsis = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onDetails) {
                ZStack {
                    Color.cineNexSurface
                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 66)
                }
                .frame(maxWidth: .infinity)
                .frame(height: presentationHeight).clipped().contentShape(Rectangle())
            }.accessibilityLabel("Details for \(item.title)")
            LinearGradient(colors: [.clear, .black.opacity(0.20), .black.opacity(0.97)],
                           startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 14) {
                Label(item.kind == .movie ? "Featured movie" : "Featured series", systemImage: "sparkle")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.cineNexAccent)
                Button(action: onDetails) {
                    Text(item.title).font(.title.bold())
                        .multilineTextAlignment(.leading).lineLimit(3)
                }.foregroundStyle(.white)
                HStack(spacing: 10) {
                    if let year = item.yearLabel { Text(year) }
                    Text(item.kind.rawValue)
                    if showRatings, let rating = item.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(.yellow)
                    }
                }.font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                if showSynopsis && featuredStyle != "compact" {
                    Text(item.synopsis).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Find sources", systemImage: "play.fill")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.black).background(Color.cineNexAccent, in: Capsule())
                    }
                    Button(action: onSave) {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            .font(.headline).frame(width: 47, height: 47).cineNexGlass(in: Circle())
                    }.foregroundStyle(.white).accessibilityLabel(saved ? "Remove from watchlist" : "Add to watchlist")
                }
            }.padding(22)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: presentationHeight, alignment: .bottomLeading)
        .background(Color.cineNexSurface)
        .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : 24))
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
    @State private var filters = CatalogFilterState()
    @State private var showingFilters = false
    @AppStorage("cinenex.browseSort") private var sortRaw = CatalogCollectionSort.relevance.rawValue
    @AppStorage("cinenex.browseLayout") private var layout = "grid"
    @AppStorage("cinenex.posterDensity") private var posterDensity = "comfortable"

    private var sort: CatalogCollectionSort { CatalogCollectionSort(rawValue: sortRaw) ?? .relevance }
    private var genres: [String] {
        Array(Set(items.flatMap { $0.genre.components(separatedBy: CharacterSet(charactersIn: ",·/")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "Unknown" })).sorted()
    }
    private var years: [Int] { Array(Set(items.map(\.year).filter { $0 > 0 })).sorted(by: >) }
    private var results: [MediaItem] {
        let matches = items.filter { filters.matches($0) }
        switch sort {
        case .relevance: return matches
        case .newest: return matches.sorted { $0.year == $1.year ? $0.title < $1.title : $0.year > $1.year }
        case .rating: return matches.sorted { ($0.rating ?? 0) == ($1.rating ?? 0) ? $0.title < $1.title : ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .title: return matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Movies and series").font(.caption.weight(.semibold)).foregroundStyle(Color.cineNexAccent)
                    Text(title == "Browse" ? "Discover" : title).font(.largeTitle.bold())
                    Text("Explore the catalog. Refine what catches your eye.").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter loaded titles", text: $filters.query).submitLabel(.search).autocorrectionDisabled()
                    if !filters.query.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { filters.query = "" }.labelStyle(.iconOnly) }
                }.padding(15).background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
                CineNexGlassGroup(spacing: 7) {
                    HStack(spacing: 7) {
                        kindButton("Everything", value: "all")
                        kindButton("Movies", value: "movies")
                        kindButton("Series", value: "series")
                    }
                }
                HStack(spacing: 12) {
                    Menu {
                        Picker("Order", selection: $sortRaw) {
                            ForEach(CatalogCollectionSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                    } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption.weight(.semibold)) }
                    Spacer()
                    Button { showingFilters = true } label: {
                        Label(filters.activeCount == 0 ? "Refine" : "Refine · \(filters.activeCount)", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.bold)).padding(.horizontal, 13).padding(.vertical, 10)
                            .cineNexGlass(in: Capsule())
                    }
                    Menu {
                        Picker("Catalog layout", selection: $layout) {
                            Text("Posters").tag("grid")
                            Text("Landscape crops").tag("landscape")
                            Text("List").tag("list")
                        }
                    } label: {
                        Image(systemName: layout == "list" ? "list.bullet" : "rectangle.grid.2x2")
                            .frame(width: 44, height: 44).cineNexGlass(in: Circle())
                    }.accessibilityLabel("Choose catalog layout")
                }.buttonStyle(.plain)
                HStack {
                    Text("\(results.count) of \(items.count) loaded titles").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if filters.activeCount > 0 { Button("Reset") { filters = CatalogFilterState() }.font(.caption.bold()) }
                }
                if results.isEmpty {
                    ContentUnavailableView("No matching titles", systemImage: "slider.horizontal.3",
                                           description: Text("Try broader filters. Only loaded catalog titles are filtered; more pages load below."))
                } else if layout == "list" {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            Button { onSelect(item) } label: {
                                HStack(spacing: 14) {
                                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 25)
                                        .frame(width: 68, height: 100).clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(item.title).font(.headline).lineLimit(2)
                                        Text([item.yearLabel, item.kind.rawValue].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(item.genre).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(.primary).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Details for \(item.title)")
                            Divider().opacity(0.2)
                        }
                    }
                } else if layout == "landscape" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 16)], alignment: .leading, spacing: 24) {
                        ForEach(results) { item in
                            Button { onSelect(item) } label: { CatalogLandscapeTile(item: item) }.buttonStyle(.plain)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: posterDensity == "compact" ? 104 : 140), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(results) { item in
                            Button { onSelect(item) } label: { CatalogPosterTile(item: item) }.buttonStyle(.plain)
                        }
                    }
                }
                if let footer { footer }
            }.padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle(title == "Browse" ? "Discover" : title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingFilters) { filterSheet }
    }

    private func kindButton(_ title: String, value: String) -> some View {
        Button { filters.kind = value } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(filters.kind == value ? Color.cineNexAccent : Color.primary)
                .cineNexGlass(in: Capsule(), prominent: filters.kind == value)
        }.buttonStyle(.plain).accessibilityAddTraits(filters.kind == value ? .isSelected : [])
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Genre") {
                    Picker("Genre", selection: $filters.genre) {
                        Text("Any genre").tag("")
                        ForEach(genres, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Release window") {
                    Picker("From year", selection: $filters.earliestYear) {
                        Text("Any year").tag(0)
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("Through year", selection: $filters.latestYear) {
                        Text("Any year").tag(0)
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    if filters.earliestYear > 0 && filters.latestYear > 0 && filters.earliestYear > filters.latestYear {
                        Text("The start year is after the end year. Adjust the window to see matches.").font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Rating & artwork") {
                    Picker("Minimum rating", selection: $filters.minimumRating) {
                        Text("Any rating").tag(0)
                        ForEach(5...9, id: \.self) { Text("\($0)+ out of 10").tag($0) }
                    }
                    Toggle("Hide unrated titles", isOn: $filters.hideUnrated)
                    Toggle("Only titles with poster artwork", isOn: $filters.requirePoster)
                    Text("Unknown ratings and years do not pass an explicit minimum or release window. These filters apply to loaded catalog metadata, not playable-source availability.").font(.caption)
                }
                Section { Button("Reset all filters") { filters = CatalogFilterState() } }
            }
            .navigationTitle("Refine discovery").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Show \(results.count) titles") { showingFilters = false } } }
        }.tint(Color.cineNexAccent).preferredColorScheme(.dark)
    }
}

private enum CatalogCollectionSort: String, CaseIterable, Identifiable {
    case relevance = "Catalog order"
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
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .bottomLeading) {
                CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 68)
                    .frame(maxWidth: .infinity).frame(height: dynamicType.isAccessibilitySize ? 230 : 340).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.86)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                HStack {
                    Label(item.kind == .movie ? "Movie" : "Series", systemImage: item.symbol)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    ShareLink(item: item.title) {
                        Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40).cineNexGlass(in: Circle())
                    }.accessibilityLabel("Share title")
                }.foregroundStyle(.white).padding(18)
            }.clipShape(RoundedRectangle(cornerRadius: 22))
            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        VStack(spacing: 12) {
            Text(item.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                if let year = item.yearLabel { metadataBadge(year) }
                metadataBadge(item.kind.rawValue)
                if showRatings, let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption.bold()).foregroundStyle(.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.cineNexSurface, in: Capsule())
                }
            }
            if !item.runtime.isEmpty {
                Label(item.runtime, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
            Text(item.genre).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }

    private func metadataBadge(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.cineNexSurface, in: Capsule())
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
