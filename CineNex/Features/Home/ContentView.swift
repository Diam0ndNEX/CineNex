import SwiftUI

struct ContentView: View {
    @State private var selectedTab = AppTab.home
    @State private var searchText = ""
    @AppStorage("cinenex.favoriteIDs") private var favoriteIDsStorage = ""
    @State private var favoriteSnapshots = FavoriteLibraryStore.shared.load()
    @StateObject private var playbackProgressStore = PlaybackProgressStore.shared

    private var favorites: Set<String> {
        Set(favoriteIDsStorage.split(separator: "\n").map(String.init))
    }
    @State private var selectedItem: MediaItem?
    @State private var activePlayerItem: MediaItem?
    @State private var watchHubItem: MediaItem?
    @State private var showingUnavailableSource = false

    @State private var catalog = CatalogCacheStore.shared.load()?.items ?? MediaItem.demoCatalog
    @State private var catalogLoading = false
    @State private var catalogError: String?
    @State private var remoteSearchResults: [MediaItem] = []
    @State private var remoteSearchQuery = ""
    @State private var remoteSearchPage = 0
    @State private var remoteSearchTotalPages = 0
    @State private var remoteSearchLoading = false
    @State private var remoteSearchLoadingMore = false
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
        let savedIDs = favorites
        let catalogFavorites = catalog.filter { savedIDs.contains($0.id) }
        let catalogIDs = Set(catalogFavorites.map { $0.id })
        let archivedFavorites = favoriteSnapshots.values
            .filter { savedIDs.contains($0.id) && !catalogIDs.contains($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return catalogFavorites + archivedFavorites
    }

    private var continueWatchingItems: [MediaItem] {
        playbackProgressStore.mostRecentlyWatched.compactMap { progress in
            guard let fraction = progress.completionFraction,
                  fraction < 0.98 else { return nil }
            let item = progress.itemSnapshot ?? catalog.first(where: { $0.id == progress.itemID })
            guard let item, item.id == progress.itemID, item.streamURL != nil else { return nil }
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
                            onPlay: { watchHubItem = item },
                            onSelectItem: { selectedItem = $0 }
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
                            onPlay: { watchHubItem = item },
                            onSelectItem: { selectedItem = $0 }
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
                            onPlay: { watchHubItem = item },
                            onSelectItem: { selectedItem = $0 }
                        )
                    }
            }
            .tabItem { Label("My List", systemImage: "bookmark.fill") }
            .tag(AppTab.library)

            NavigationStack {
                OfflineLibraryView { download, localURL in
                    activePlayerItem = MediaItem(
                        id: "offline-\(download.id)",
                        title: download.title,
                        kind: .movie,
                        year: 0,
                        genre: "Offline",
                        synopsis: "Downloaded for offline playback.",
                        symbol: "arrow.down.circle.fill",
                        runtime: "Offline media",
                        streamURL: localURL
                    )
                }
            }
            .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
            .tag(AppTab.downloads)

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
        .sheet(item: $watchHubItem) { item in
            WatchHubView(item: item, onPlayDirect: { play($0) }, onSelectItem: { watchHubItem = $0 })
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
                        watchHubItem = featured
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
                        ForEach(Array(displayedSearchResults.enumerated()), id: \.element.id) { index, item in
                            MediaPosterCard(item: item) {
                                selectedItem = item
                            }
                            .onAppear {
                                let isRemoteSearch = !remoteSearchQuery.isEmpty &&
                                    remoteSearchQuery.caseInsensitiveCompare(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                                let isNearEnd = index >= max(0, displayedSearchResults.count - 4)
                                if isRemoteSearch && isNearEnd && remoteSearchPage < remoteSearchTotalPages {
                                    Task { await loadMoreTMDBSearchResults() }
                                }
                            }
                        }
                    }

                    if remoteSearchQuery.caseInsensitiveCompare(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame,
                       remoteSearchPage > 0,
                       remoteSearchPage < remoteSearchTotalPages {
                        Button {
                            Task { await loadMoreTMDBSearchResults() }
                        } label: {
                            HStack(spacing: 10) {
                                if remoteSearchLoadingMore {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle")
                                }
                                Text(remoteSearchLoadingMore ? "Loading more titles…" : "Load more results")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(remoteSearchLoading || remoteSearchLoadingMore)
                        .accessibilityHint("Loads the next page of TMDB search results")
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
                            .contextMenu {
                                if showProgress {
                                    Button(role: .destructive) {
                                        playbackProgressStore.remove(itemID: item.id)
                                    } label: {
                                        Label("Remove from Continue Watching", systemImage: "xmark.circle")
                                    }
                                }
                            }
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
            catalogError = nil
            return
        }
        guard force || !catalogLoading else { return }

        catalogLoading = true
        defer { catalogLoading = false }
        do {
            let liveCatalog = try await TMDBCatalogProvider(readAccessToken: token).fetchCatalog()
            guard !Task.isCancelled else { return }
            guard !liveCatalog.isEmpty else {
                catalogError = "TMDB returned no trending titles. Showing the last saved catalog."
                return
            }
            catalog = liveCatalog
            CatalogCacheStore.shared.save(liveCatalog)
            catalogError = nil
        } catch is CancellationError {
            return
        } catch {
            catalogError = error.localizedDescription
            if catalog.isEmpty {
                catalog = CatalogCacheStore.shared.load()?.items ?? MediaItem.demoCatalog
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
            let page = try await TMDBCatalogProvider(readAccessToken: token).searchPage(query: query, page: 1)
            guard !Task.isCancelled,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(query) == .orderedSame else {
                return
            }
            remoteSearchResults = page.items
            remoteSearchQuery = query
            remoteSearchPage = page.page
            remoteSearchTotalPages = page.totalPages
            if page.items.isEmpty { remoteSearchError = "TMDB found no matching movies or series." }
        } catch is CancellationError {
            return
        } catch {
            remoteSearchError = error.localizedDescription
            remoteSearchResults = []
            remoteSearchQuery = ""
            remoteSearchPage = 0
            remoteSearchTotalPages = 0
        }
    }

    @MainActor
    private func loadMoreTMDBSearchResults() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              query.caseInsensitiveCompare(remoteSearchQuery) == .orderedSame,
              !remoteSearchLoading,
              !remoteSearchLoadingMore,
              remoteSearchPage > 0,
              remoteSearchPage < remoteSearchTotalPages else {
            return
        }
        guard let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            remoteSearchError = "Connect TMDB in Tracking to load more results."
            return
        }

        remoteSearchLoadingMore = true
        remoteSearchError = nil
        defer { remoteSearchLoadingMore = false }
        do {
            let nextPage = remoteSearchPage + 1
            let page = try await TMDBCatalogProvider(readAccessToken: token).searchPage(query: query, page: nextPage)
            guard !Task.isCancelled,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(query) == .orderedSame,
                  remoteSearchQuery.caseInsensitiveCompare(query) == .orderedSame else {
                return
            }

            var seenIDs = Set(remoteSearchResults.map(\.id))
            let uniqueItems = page.items.filter { seenIDs.insert($0.id).inserted }
            remoteSearchResults.append(contentsOf: uniqueItems)
            remoteSearchPage = page.page
            remoteSearchTotalPages = page.totalPages
            if uniqueItems.isEmpty && page.hasMorePages {
                remoteSearchError = "No new titles on this page. You can load the next page to continue."
            }
        } catch is CancellationError {
            return
        } catch {
            remoteSearchError = error.localizedDescription
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
        if updatedFavorites.contains(item.id) {
            FavoriteLibraryStore.shared.save(item)
        } else {
            FavoriteLibraryStore.shared.remove(itemID: item.id)
        }
        favoriteSnapshots = FavoriteLibraryStore.shared.load()
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
    case downloads
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
                Text(([item.yearLabel, item.genre].compactMap { $0 }).joined(separator: " · "))
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
    @StateObject private var offlineDownloadStore = OfflineDownloadStore.shared
    @State private var offlineDownloadMessage: String?
    @State private var showingOfflineDownloadMessage = false

    let item: MediaItem
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    let onPlay: () -> Void
    let onSelectItem: (MediaItem) -> Void
    @State private var extendedDetails: TMDBTitleDetails?
    @State private var detailsLoading = false
    @State private var detailsError: String?
    @State private var selectedSeason: TMDBTitleSeason?

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
                    Text(([item.yearLabel, item.kind.rawValue, item.genre, item.runtime].compactMap { $0 }).joined(separator: "  •  "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let rating = item.rating {
                        Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                    }
                    if let tagline = extendedDetails?.tagline,
                       !tagline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(tagline)
                            .font(.subheadline.italic())
                            .foregroundStyle(Color.cineNexAccent)
                    }
                    Text(item.synopsis)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if detailsLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading full details…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let details = extendedDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("More details")
                            .font(.title3.bold())
                        if let runtime = details.runtimeLabel {
                            detailRow("Runtime", value: runtime, symbol: "clock")
                        }
                        if let status = details.status, !status.isEmpty {
                            detailRow("Status", value: status, symbol: "info.circle")
                        }
                        if !details.genreNames.isEmpty {
                            detailRow("Genres", value: details.genreNames.joined(separator: " · "), symbol: "tag")
                        }
                        if item.kind == .series {
                            if let seasons = details.numberOfSeasons, seasons > 0 {
                                detailRow("Seasons", value: String(seasons), symbol: "square.stack")
                            }
                            if let episodes = details.numberOfEpisodes, episodes > 0 {
                                detailRow("Episodes", value: String(episodes), symbol: "play.rectangle")
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                } else if let detailsError {
                    Label(detailsError, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let details = extendedDetails {
                    if item.kind == .series, !details.seasonSummaries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Seasons")
                                .font(.title3.bold())
                            ForEach(details.seasonSummaries) { season in
                                Button {
                                    selectedSeason = season
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                    CachedPosterImage(
                                        url: season.posterURL,
                                        fallbackSymbol: "tv",
                                        symbolSize: 22
                                    )
                                    .frame(width: 68, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(season.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        HStack(spacing: 8) {
                                            if let episodeCount = season.episodeCount, episodeCount > 0 {
                                                Text("\(episodeCount) episodes")
                                            }
                                            if let airYear = season.airYear {
                                                Text(String(airYear))
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                                           !overview.isEmpty {
                                            Text(overview)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityHint("Shows episodes in \(season.displayName)")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !details.castMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cast")
                                .font(.title3.bold())
                            ForEach(Array(details.castMembers.enumerated()), id: \.offset) { _, member in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.name ?? "Unknown performer")
                                        .font(.subheadline.weight(.semibold))
                                    if let character = member.character?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !character.isEmpty {
                                        Text(character)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !details.directorNames.isEmpty || !details.creatorNames.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Crew")
                                .font(.title3.bold())
                            if !details.directorNames.isEmpty {
                                detailRow("Director", value: details.directorNames.joined(separator: ", "), symbol: "megaphone")
                            }
                            if !details.creatorNames.isEmpty {
                                detailRow("Created by", value: details.creatorNames.joined(separator: ", "), symbol: "person.2")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if let trailerURL = details.trailerURL {
                        Link(destination: trailerURL) {
                            Label("Watch trailer on YouTube", systemImage: "play.rectangle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Color.cineNexAccent, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                        .accessibilityHint("Opens the selected official or first available TMDB trailer in YouTube")
                    }

                    let recommendations = details.recommendedItems(for: item.kind)
                    if !recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You might also like")
                                .font(.title3.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(recommendations) { recommendation in
                                        VStack(alignment: .leading, spacing: 7) {
                                            MediaPosterCard(item: recommendation) {
                                                onSelectItem(recommendation)
                                            }
                                            .frame(width: 132)
                                            Text(recommendation.title)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(2)
                                                .frame(width: 132, alignment: .leading)
                                            if recommendation.year > 0 {
                                                Text(String(recommendation.year))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 132, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
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
                } else if let sourceURL = item.streamURL {
                    let eligible = OfflineDownloadStore.supportsOfflineDownload(from: sourceURL)
                    Button {
                        do {
                            let record = try offlineDownloadStore.enqueue(title: item.title, sourceURL: sourceURL)
                            offlineDownloadMessage = record.status == .completed
                                ? "This title is already available offline."
                                : "Added to offline downloads."
                        } catch {
                            offlineDownloadMessage = error.localizedDescription
                        }
                        showingOfflineDownloadMessage = true
                    } label: {
                        Label("Download for Offline", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!eligible)
                    .accessibilityHint(
                        eligible
                            ? "Downloads this HLS stream for offline playback"
                            : "This source is not a supported HLS playlist"
                    )
                    if !eligible {
                        Text("Offline downloads require a compatible HTTPS HLS playlist. This source cannot be downloaded in CineNex.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            await loadExtendedDetails()
        }
        .sheet(item: $selectedSeason) { season in
            SeasonEpisodesView(item: item, season: season)
        }
        .alert("Offline Download", isPresented: $showingOfflineDownloadMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(offlineDownloadMessage ?? "The download request has been processed.")
        }
    }

    private func detailRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.cineNexAccent)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    @MainActor
    private func loadExtendedDetails() async {
        guard item.metadataProvider == "tmdb" else {
            extendedDetails = nil
            detailsError = nil
            return
        }
        guard let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            detailsError = nil
            return
        }

        detailsLoading = true
        detailsError = nil
        defer { detailsLoading = false }
        do {
            extendedDetails = try await TMDBCatalogProvider(readAccessToken: token).fetchDetails(for: item)
        } catch is CancellationError {
            return
        } catch {
            detailsError = "Additional details are temporarily unavailable."
        }
    }
}

#Preview {
    ContentView()
}
