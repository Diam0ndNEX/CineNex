import SwiftUI

struct ContentView: View {
    @State private var selectedTab = AppTab.home
    @State private var searchText = ""
    @AppStorage("cinenex.favoriteIDs") private var favoriteIDsStorage = ""
    @StateObject private var playbackProgressStore = PlaybackProgressStore.shared

    private var favorites: Set<String> {
        Set(favoriteIDsStorage.split(separator: "\n").map(String.init))
    }
    @State private var selectedItem: MediaItem?
    @State private var activePlayerItem: MediaItem?
    @State private var showingUnavailableSource = false

    @State private var catalog = MediaItem.demoCatalog
    @State private var catalogLoading = false
    @State private var catalogError: String?
    @State private var remoteSearchResults: [MediaItem] = []
    @State private var remoteSearchQuery = ""
    @State private var remoteSearchLoading = false
    @State private var remoteSearchError: String?
    @State private var selectedSearchKind = SearchKind.all
    @State private var selectedSearchSort = SearchSort.relevance

    private var filteredCatalog: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalog }
        return catalog.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.genre.localizedCaseInsensitiveContains(query)
                || $0.kind.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedSearchResults: [MediaItem] {
        let source: [MediaItem]
        if !remoteSearchQuery.isEmpty,
           remoteSearchQuery.caseInsensitiveCompare(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            source = remoteSearchResults
        } else {
            source = filteredCatalog
        }

        let kindFiltered = source.filter { item in
            switch selectedSearchKind {
            case .all: return true
            case .movies: return item.kind == .movie
            case .series: return item.kind == .series
            }
        }

        switch selectedSearchSort {
        case .relevance:
            return kindFiltered
        case .title:
            return kindFiltered.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .newest:
            return kindFiltered.sorted {
                if $0.year != $1.year { return $0.year > $1.year }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .highestRated:
            return kindFiltered.sorted {
                let left = $0.rating ?? -1
                let right = $1.rating ?? -1
                if left != right { return left > right }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    private var favoriteItems: [MediaItem] {
        catalog.filter { favorites.contains($0.id) }
    }

    private var continueWatchingItems: [MediaItem] {
        playbackProgressStore.mostRecentlyWatched.compactMap { progress in
            guard let item = catalog.first(where: { $0.id == progress.itemID }),
                  item.streamURL != nil,
                  let fraction = progress.completionFraction,
                  fraction < 0.98 else { return nil }
            return item
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                homeScreen
                    .navigationDestination(item: $selectedItem) { item in
                        MediaDetailView(
                            item: item,
                            isFavorite: favorites.contains(item.id),
                            onFavoriteToggle: { toggleFavorite(item) },
                            onPlay: { play(item) }
                        )
                    }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                searchScreen
                    .navigationDestination(item: $selectedItem) { item in
                        MediaDetailView(
                            item: item,
                            isFavorite: favorites.contains(item.id),
                            onFavoriteToggle: { toggleFavorite(item) },
                            onPlay: { play(item) }
                        )
                    }
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(AppTab.search)

            NavigationStack {
                libraryScreen
                    .navigationDestination(item: $selectedItem) { item in
                        MediaDetailView(
                            item: item,
                            isFavorite: favorites.contains(item.id),
                            onFavoriteToggle: { toggleFavorite(item) },
                            onPlay: { play(item) }
                        )
                    }
            }
            .tabItem { Label("My List", systemImage: "bookmark.fill") }
            .tag(AppTab.library)

            NavigationStack {
                TrackingView()
            }
            .tabItem { Label("Tracking", systemImage: "arrow.triangle.2.circlepath") }
            .tag(AppTab.tracking)
        }
        .tint(Color.cineNexAccent)
        .task { await loadCatalog() }
        .fullScreenCover(item: $activePlayerItem) { item in
            PlayerView(item: item, progressStore: playbackProgressStore)
        }
        .alert("Playback unavailable", isPresented: $showingUnavailableSource) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This title has no playable source yet. CineNex only plays media supplied by a compatible, authorized provider.")
        }
    }

    private var homeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let catalogError {
                    Label(catalogError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }

                if let featured = catalog.first {
                    FeaturedBanner(item: featured) {
                        selectedItem = featured
                    } onPlay: {
                        play(featured)
                    }
                }

                if !continueWatchingItems.isEmpty {
                    mediaSection(title: "Continue Watching", subtitle: "Pick up where you left off", items: continueWatchingItems, showProgress: true)
                }

                mediaSection(title: "Popular on CineNex", subtitle: "A first look at your next favorite", items: catalog)

                let movies = catalog.filter { $0.kind == .movie }
                mediaSection(title: "Movies", subtitle: "Stories for every mood", items: movies)

                let series = catalog.filter { $0.kind == .series }
                mediaSection(title: "Series", subtitle: "Find your next episode", items: series)
            }
            .padding(.bottom, 24)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .refreshable { await loadCatalog(force: true) }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var searchScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Discover")
                    .font(.largeTitle.bold())
                TextField("Search movies, series, genres…", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Search movies and series")
                    .submitLabel(.search)
                    .onSubmit { Task { await searchTMDB() } }

                Button {
                    Task { await searchTMDB() }
                } label: {
                    HStack {
                        if remoteSearchLoading { ProgressView().tint(.white) } else { Image(systemName: "globe") }
                        Text(remoteSearchLoading ? "Searching TMDB…" : "Search TMDB")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(14)
                    .background(Color.cineNexAccent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(remoteSearchLoading || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let remoteSearchError {
                    Text(remoteSearchError)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Picker("Media type", selection: $selectedSearchKind) {
                        ForEach(SearchKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Filter search results by media type")

                    Picker("Sort", selection: $selectedSearchSort) {
                        ForEach(SearchSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Sort search results")
                }

                Text("\(displayedSearchResults.count) titles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if displayedSearchResults.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "Search CineNex" : "No matching titles", systemImage: "magnifyingglass", description: Text(searchText.isEmpty ? "Search the local catalog or search TMDB for movies and series." : "Try another title or change the media type filter."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(displayedSearchResults) { item in
                            MediaPosterCard(item: item) {
                                selectedItem = item
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Search")
    }

    private var libraryScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("My List")
                    .font(.largeTitle.bold())
                Text("Your saved titles, all in one place.")
                    .foregroundStyle(.secondary)

                if favoriteItems.isEmpty {
                    ContentUnavailableView(
                        "Your list is empty",
                        systemImage: "bookmark",
                        description: Text("Open a title and tap Save to add it here.")
                    )
                    .padding(.top, 45)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(favoriteItems) { item in
                            MediaPosterCard(item: item) {
                                selectedItem = item
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("My List")
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                Text("CineNex")
                    .font(.title2.bold())
                    .tracking(-0.6)
            }
            Spacer()
            Button {
                Task { await loadCatalog(force: true) }
            } label: {
                if catalogLoading {
                    ProgressView()
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.cineNexSurface, in: Circle())
                }
            }
            .disabled(catalogLoading)
            .accessibilityLabel("Refresh catalog")
            Button {
                selectedTab = .search
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.cineNexSurface, in: Circle())
            }
            .accessibilityLabel("Open search")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func mediaSection(title: String, subtitle: String, items: [MediaItem], showProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            MediaPosterCard(item: item) {
                                if showProgress {
                                    play(item)
                                } else {
                                    selectedItem = item
                                }
                            }
                            .frame(width: 148)
                            if showProgress,
                               let progress = playbackProgressStore.progress(for: item.id),
                               let fraction = progress.completionFraction {
                                ProgressView(value: fraction)
                                    .tint(Color.cineNexAccent)
                                    .frame(width: 148)
                                Text("Resume · \(Int(progress.position / 60)) min watched")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 148, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @MainActor
    private func loadCatalog(force: Bool = false) async {
        let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            catalog = MediaItem.demoCatalog
            catalogError = nil
            return
        }
        guard force || !catalogLoading else { return }

        catalogLoading = true
        defer { catalogLoading = false }
        do {
            let liveCatalog = try await TMDBCatalogProvider(readAccessToken: token).fetchCatalog()
            guard !Task.isCancelled else { return }
            catalog = liveCatalog.isEmpty ? MediaItem.demoCatalog : liveCatalog
            catalogError = liveCatalog.isEmpty ? "TMDB returned no trending titles. Showing the demo catalog instead." : nil
        } catch is CancellationError {
            return
        } catch {
            catalogError = error.localizedDescription
            if catalog.isEmpty {
                catalog = MediaItem.demoCatalog
            }
        }
    }

    @MainActor
    private func searchTMDB() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            remoteSearchError = "Connect TMDB in Tracking to search the full catalog."
            remoteSearchQuery = ""
            return
        }
        remoteSearchLoading = true
        remoteSearchError = nil
        defer { remoteSearchLoading = false }
        do {
            let results = try await TMDBCatalogProvider(readAccessToken: token).search(query: query)
            guard !Task.isCancelled else { return }
            remoteSearchResults = results
            remoteSearchQuery = query
            if results.isEmpty { remoteSearchError = "TMDB found no matching movies or series." }
        } catch is CancellationError {
            return
        } catch {
            remoteSearchError = error.localizedDescription
            remoteSearchResults = []
            remoteSearchQuery = ""
        }
    }

    private func toggleFavorite(_ item: MediaItem) {
        var updatedFavorites = favorites
        if updatedFavorites.contains(item.id) {
            updatedFavorites.remove(item.id)
        } else {
            updatedFavorites.insert(item.id)
        }
        favoriteIDsStorage = updatedFavorites.sorted().joined(separator: "\n")
    }

    private func play(_ item: MediaItem) {
        guard item.streamURL != nil else {
            showingUnavailableSource = true
            return
        }
        activePlayerItem = item
    }
}

private enum AppTab: Hashable {
    case home
    case search
    case library
    case tracking
}

private enum SearchKind: String, CaseIterable, Identifiable {
    case all
    case movies
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .series: return "Series"
        }
    }
}

private enum SearchSort: String, CaseIterable, Identifiable {
    case relevance
    case title
    case newest
    case highestRated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: return "Relevance"
        case .title: return "Title"
        case .newest: return "Newest"
        case .highestRated: return "Top rated"
        }
    }
}

extension Color {
    static let cineNexBackground = Color(red: 0.035, green: 0.043, blue: 0.065)
    static let cineNexSurface = Color(red: 0.09, green: 0.105, blue: 0.145)
    static let cineNexAccent = Color(red: 0.42, green: 0.35, blue: 1.0)
}

private struct FeaturedBanner: View {
    let item: MediaItem
    let onDetails: () -> Void
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.16, blue: 0.43),
                            Color(red: 0.08, green: 0.12, blue: 0.25),
                            Color.cineNexSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 240, height: 240)
                .offset(x: 180, y: -90)
            Image(systemName: item.symbol)
                .font(.system(size: 94, weight: .light))
                .foregroundStyle(.white.opacity(0.20))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)

            VStack(alignment: .leading, spacing: 12) {
                Label("FEATURED SAMPLE", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(Color(red: 0.78, green: 0.73, blue: 1))
                Text(item.title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                Text("\(item.year)  •  \(item.genre)  •  \(item.runtime)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .foregroundStyle(.black)
                            .background(.white, in: Capsule())
                    }
                    Button(action: onDetails) {
                        Label("Details", systemImage: "info.circle")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.13), in: Capsule())
                    }
                }
            }
            .padding(22)
        }
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
    }
}

private struct MediaPosterCard: View {
    let item: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cineNexAccent.opacity(0.42),
                                    Color.cineNexSurface,
                                    Color(red: 0.13, green: 0.20, blue: 0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    CachedPosterImage(
                        url: item.posterURL,
                        fallbackSymbol: item.symbol,
                        symbolSize: 38
                    )
                    VStack {
                        HStack {
                            Text(item.kind.rawValue.uppercased())
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.8)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.35), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(item.year) · \(item.genre)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(item.kind.rawValue), \(item.year)")
    }
}

private struct MediaDetailView: View {
    let item: MediaItem
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    let onPlay: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [Color.cineNexAccent.opacity(0.5), Color.cineNexSurface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    CachedPosterImage(
                        url: item.posterURL,
                        fallbackSymbol: item.symbol,
                        symbolSize: 88
                    )
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.largeTitle.bold())
                    Text("\(item.year)  •  \(item.kind.rawValue)  •  \(item.genre)  •  \(item.runtime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let rating = item.rating {
                        Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                    }
                    Text(item.synopsis)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label(item.streamURL == nil ? "Source unavailable" : "Play now", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(item.streamURL == nil)

                    Button(action: onFavoriteToggle) {
                        Label(isFavorite ? "Saved" : "Save", systemImage: isFavorite ? "bookmark.fill" : "bookmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }

                if item.streamURL == nil {
                    Label("Playback will become available when a compatible provider supplies a source.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}
