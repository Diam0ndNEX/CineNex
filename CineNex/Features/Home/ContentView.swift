import SwiftUI

private enum HomeCategory: String, CaseIterable, Identifiable {
    case forYou
    case movies
    case series
    case myList

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .movies: return "Movies"
        case .series: return "Series"
        case .myList: return "My List"
        }
    }

    var symbol: String {
        switch self {
        case .forYou: return "sparkles"
        case .movies: return "film"
        case .series: return "tv"
        case .myList: return "bookmark"
        }
    }
}

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
    @State private var showingAppearanceSettings = false
    @State private var selectedHomeCategory = HomeCategory.forYou
    @AppStorage("cinenex.homeExperience") private var selectedHomeExperience = "moviesAndSeries"
    @State private var selectedAnime: AnimeTitle?
    @State private var animeCatalog: [AnimeTitle] = []
    @State private var animeLoading = false
    @State private var animeError: String?
    @State private var animeSearchText = ""
    @State private var animeSearchResults: [AnimeTitle] = []
    @State private var animeSearchLoading = false
    @State private var animeSearchError: String?
    @State private var hasSearchedAnime = false
    @StateObject private var animeProgressStore = AnimeProgressStore.shared

    @State private var catalog = CatalogCacheStore.shared.load()?.items ?? []
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
            guard let item, item.id == progress.itemID else { return nil }
            return item
        }
    }

    private var featuredHomeItem: MediaItem? {
        switch selectedHomeCategory {
        case .forYou:
            return catalog.first
        case .movies:
            return catalog.first(where: { $0.kind == .movie })
        case .series:
            return catalog.first(where: { $0.kind == .series })
        case .myList:
            return nil
        }
    }

    private var homeCategoryItems: [MediaItem] {
        switch selectedHomeCategory {
        case .forYou:
            return catalog
        case .movies:
            return catalog.filter { $0.kind == .movie }
        case .series:
            return catalog.filter { $0.kind == .series }
        case .myList:
            return favoriteItems
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
            .tabItem { Label(selectedHomeExperience == "anime" ? "Anime List" : "My List", systemImage: "bookmark.fill") }
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

    }

    private var homeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                experiencePicker

                if selectedHomeExperience == "anime" {
                    animeHomeContent
                } else {
                    moviesAndSeriesHomeContent
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .refreshable {
            if selectedHomeExperience == "anime" {
                await loadAnimeCatalog(force: true)
            } else {
                await loadCatalog(force: true)
            }
        }
        .task(id: selectedHomeExperience) {
            if selectedHomeExperience == "anime" {
                await loadAnimeCatalog()
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime, progressStore: animeProgressStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var experiencePicker: some View {
        Picker("Content experience", selection: $selectedHomeExperience) {
            Text("Movies & Series").tag("moviesAndSeries")
            Text("Anime").tag("anime")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .accessibilityLabel("Choose Movies and Series or Anime")
    }

    private var moviesAndSeriesHomeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Find your next obsession")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text("A world of stories, picked for your mood.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)

            homeCategoryPicker

            if let catalogError {
                Label(catalogError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            if let featured = featuredHomeItem {
                FeaturedBanner(item: featured) {
                    selectedItem = featured
                } onPlay: {
                    watchHubItem = featured
                }
            }

            switch selectedHomeCategory {
            case .forYou:
                if !continueWatchingItems.isEmpty {
                    mediaSection(title: "Continue Watching", subtitle: "Pick up right where you left off", items: continueWatchingItems, showProgress: true)
                }
                mediaSection(title: "Popular right now", subtitle: "Discover something worth watching", items: catalog)
                let movies = catalog.filter { $0.kind == .movie }
                if !movies.isEmpty {
                    mediaSection(title: "Movies for every mood", subtitle: "Big stories, one great night", items: movies)
                }
                let series = catalog.filter { $0.kind == .series }
                if !series.isEmpty {
                    mediaSection(title: "Series to get into", subtitle: "Your next episode starts here", items: series)
                }
            case .movies:
                if homeCategoryItems.isEmpty {
                    emptyHomeCategory(title: "No movies yet", message: "Refresh the catalog to discover more movies. Connecting TMDB adds expanded metadata but is optional.")
                } else {
                    mediaSection(title: "Explore movies", subtitle: "Choose your next feature", items: homeCategoryItems)
                }
            case .series:
                if homeCategoryItems.isEmpty {
                    emptyHomeCategory(title: "No series yet", message: "Refresh the catalog or connect TMDB in Tracking to discover series.")
                } else {
                    mediaSection(title: "Explore series", subtitle: "Find a story to stay with", items: homeCategoryItems)
                }
            case .myList:
                if homeCategoryItems.isEmpty {
                    ContentUnavailableView(
                        "Your list is empty",
                        systemImage: "bookmark",
                        description: Text("Save a title from its details to keep it close at hand.")
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(homeCategoryItems) { item in
                            MediaPosterCard(item: item) {
                                selectedItem = item
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var animeHomeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your anime universe")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text("Trending series, films, and your episode progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)

            if let animeError {
                Label(animeError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            if let featured = animeCatalog.first {
                AnimeFeaturedBanner(anime: featured) {
                    selectedAnime = featured
                }
            }

            if animeLoading && animeCatalog.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.cineNexAccent)
                    Text("Loading trending anime…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            } else if animeCatalog.isEmpty {
                ContentUnavailableView(
                    "Anime is temporarily unavailable",
                    systemImage: "sparkles.tv",
                    description: Text("Check your connection and pull down to retry loading the public AniList catalog.")
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trending anime")
                            .font(.title2.bold())
                        Text("Live metadata from AniList")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)

                    AnimePosterShelf(
                        items: animeCatalog,
                        progressStore: animeProgressStore
                    ) { anime in
                        selectedAnime = anime
                    }
                }
            }
        }
    }

    private var homeCategoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HomeCategory.allCases) { category in
                    let isSelected = selectedHomeCategory == category
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedHomeCategory = category
                        }
                    } label: {
                        Label(category.title, systemImage: category.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .background(
                                isSelected ? Color.cineNexAccent : Color.cineNexSurface,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityLabel("Home categories")
    }

    private func emptyHomeCategory(title: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: "square.stack", description: Text(message))
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    private var searchScreen: some View {
        Group {
            if selectedHomeExperience == "anime" {
                animeSearchScreen
            } else {
                moviesAndSeriesSearchScreen
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime, progressStore: animeProgressStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var animeSearchScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Find anime")
                    .font(.largeTitle.bold())
                Text("Search AniList for anime titles, films, and series.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Search anime titles…", text: $animeSearchText)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Search anime titles")
                    .submitLabel(.search)
                    .onSubmit { Task { await searchAniList() } }

                Button {
                    Task { await searchAniList() }
                } label: {
                    HStack(spacing: 10) {
                        if animeSearchLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(animeSearchLoading ? "Searching AniList…" : "Search AniList")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(14)
                    .background(Color.cineNexAccent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(animeSearchLoading || animeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let animeSearchError {
                    Label(animeSearchError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if animeSearchLoading && animeSearchResults.isEmpty {
                    ProgressView("Searching anime…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 35)
                } else if hasSearchedAnime && animeSearchResults.isEmpty && animeSearchError == nil {
                    ContentUnavailableView(
                        "No anime found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different title or spelling.")
                    )
                    .padding(.top, 24)
                } else if !animeSearchResults.isEmpty {
                    Text("\(animeSearchResults.count) results")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(animeSearchResults) { anime in
                            AnimePosterCard(
                                anime: anime,
                                watchedEpisodes: animeProgressStore.watchedEpisodeCount(for: anime)
                            ) {
                                selectedAnime = anime
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Search anime",
                        systemImage: "sparkles",
                        description: Text("Enter an anime title to find results from AniList.")
                    )
                    .padding(.top, 20)
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Anime Search")
    }

    private var moviesAndSeriesSearchScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Discover")
                    .font(.largeTitle.bold())
                TextField("Search movies and series…", text: $searchText)
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
                        Text(remoteSearchLoading ? "Searching titles…" : "Search titles")
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
                    ContentUnavailableView(searchText.isEmpty ? "Search CineNex" : "No matching titles", systemImage: "magnifyingglass", description: Text(searchText.isEmpty ? "Search CineNex's catalog for movies and series." : "Try another title or change the media type filter."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(displayedSearchResults) { item in
                            MediaPosterCard(item: item) {
                                selectedItem = item
                            }
                            .onAppear {
                                let isRemoteSearch = !remoteSearchQuery.isEmpty &&
                                    remoteSearchQuery.caseInsensitiveCompare(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                                let nearEndIDs = Set(displayedSearchResults.suffix(4).map(\.id))
                                if isRemoteSearch &&
                                    nearEndIDs.contains(item.id) &&
                                    remoteSearchPage < remoteSearchTotalPages {
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
        Group {
            if selectedHomeExperience == "anime" {
                animeLibraryScreen
            } else {
                moviesAndSeriesLibraryScreen
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime, progressStore: animeProgressStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var animeLibraryScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Anime List")
                    .font(.largeTitle.bold())
                Text("Anime you have started tracking, with progress saved on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if animeProgressStore.trackedAnime.isEmpty {
                    ContentUnavailableView(
                        "No anime tracked yet",
                        systemImage: "bookmark",
                        description: Text("Open an anime title and update Episodes watched to add it to your Anime List.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(animeProgressStore.trackedAnime) { anime in
                            AnimePosterCard(
                                anime: anime,
                                watchedEpisodes: animeProgressStore.watchedEpisodeCount(for: anime)
                            ) {
                                selectedAnime = anime
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Anime List")
    }

    private var moviesAndSeriesLibraryScreen: some View {
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
                Task {
                    if selectedHomeExperience == "anime" {
                        await loadAnimeCatalog(force: true)
                    } else {
                        await loadCatalog(force: true)
                    }
                }
            } label: {
                if selectedHomeExperience == "anime" ? animeLoading : catalogLoading {
                    ProgressView()
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.cineNexSurface, in: Circle())
                }
            }
            .disabled(selectedHomeExperience == "anime" ? animeLoading : catalogLoading)
            .accessibilityLabel(selectedHomeExperience == "anime" ? "Refresh anime catalog" : "Refresh catalog")
            Button {
                selectedTab = .search
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.cineNexSurface, in: Circle())
            }
            .accessibilityLabel("Open search")
            Button {
                showingAppearanceSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.cineNexSurface, in: Circle())
            }
            .accessibilityLabel("Customize appearance")
            .sheet(isPresented: $showingAppearanceSettings) {
                AppearanceSettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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
    private func searchAniList() async {
        let query = animeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            animeSearchError = "Enter an anime title to search AniList."
            animeSearchResults = []
            hasSearchedAnime = false
            return
        }
        guard !animeSearchLoading else { return }

        animeSearchLoading = true
        animeSearchError = nil
        hasSearchedAnime = true
        defer { animeSearchLoading = false }

        do {
            let results = try await AniListCatalogProvider().searchAnime(query: query)
            guard !Task.isCancelled else { return }
            animeSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            animeSearchError = error.localizedDescription
        }
    }

    @MainActor
    private func loadAnimeCatalog(force: Bool = false) async {
        guard !animeLoading else { return }
        guard force || animeCatalog.isEmpty else { return }

        animeLoading = true
        animeError = nil
        defer { animeLoading = false }

        do {
            let results = try await AniListCatalogProvider().fetchTrending()
            guard !Task.isCancelled else { return }
            animeCatalog = results
            if results.isEmpty {
                animeError = "AniList did not return trending anime. Pull down to try again."
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            animeError = error.localizedDescription
        }
    }

    @MainActor
    private func loadCatalog(force: Bool = false) async {
        let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard force || !catalogLoading else { return }

        catalogLoading = true
        defer { catalogLoading = false }
        do {
            let liveCatalog: [MediaItem]
            if token.isEmpty {
                liveCatalog = try await CinemetaCatalogProvider().fetchCatalog()
            } else {
                liveCatalog = try await TMDBCatalogProvider(readAccessToken: token).fetchCatalog()
            }
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
                catalog = CatalogCacheStore.shared.load()?.items ?? []
            }
        }
    }

    @MainActor
    private func searchTMDB() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        remoteSearchLoading = true
        remoteSearchError = nil
        defer { remoteSearchLoading = false }
        do {
            let results: [MediaItem]
            let pageNumber: Int
            let totalPages: Int
            if token.isEmpty {
                results = try await CinemetaCatalogProvider().search(query: query)
                pageNumber = 1
                totalPages = 1
            } else {
                let page = try await TMDBCatalogProvider(readAccessToken: token).searchPage(query: query, page: 1)
                results = page.items
                pageNumber = page.page
                totalPages = page.totalPages
            }
            guard !Task.isCancelled,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(query) == .orderedSame else {
                return
            }
            remoteSearchResults = results
            remoteSearchQuery = query
            remoteSearchPage = pageNumber
            remoteSearchTotalPages = totalPages
            if results.isEmpty { remoteSearchError = "No matching movies or series were found." }
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
            watchHubItem = item
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

    static var cineNexAccent: Color {
        switch UserDefaults.standard.string(forKey: "cinenex.accentPreset") ?? "violet" {
        case "blue":
            return Color(red: 0.24, green: 0.52, blue: 1.0)
        case "rose":
            return Color(red: 0.95, green: 0.32, blue: 0.58)
        case "teal":
            return Color(red: 0.12, green: 0.72, blue: 0.68)
        case "amber":
            return Color(red: 1.0, green: 0.62, blue: 0.22)
        default:
            return Color(red: 0.58, green: 0.36, blue: 0.98)
        }
    }
}

private struct FeaturedBanner: View {
    let item: MediaItem
    let onDetails: () -> Void
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedPosterImage(
                url: item.posterURL,
                fallbackSymbol: item.symbol,
                symbolSize: 94
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: Color(red: 0.035, green: 0.043, blue: 0.065).opacity(0.42), location: 0.36),
                    .init(color: Color(red: 0.035, green: 0.043, blue: 0.065).opacity(0.98), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.cineNexAccent.opacity(0.26), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 1)
                .offset(x: 185, y: -110)

            VStack(alignment: .leading, spacing: 12) {
                Label((item.metadataProvider == "tmdb" || item.metadataProvider == "cinemeta") ? "TRENDING PICK" : "FEATURED SAMPLE", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(Color.cineNexAccent)
                Text(item.title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
                HStack(spacing: 7) {
                    if let year = item.yearLabel {
                        Text(year)
                        Text("·")
                    }
                    Text(item.kind.rawValue)
                    Text("·")
                    Text(item.genre)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                if let rating = item.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                }
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Find a source", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.cineNexAccent, in: Capsule())
                    }
                    .accessibilityHint("Finds available playback sources for this title")
                    Button(action: onDetails) {
                        Label("Details", systemImage: "info.circle")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                }
            }
            .padding(22)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
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
                                .background(.black.opacity(0.42), in: Capsule())
                            Spacer()
                            if let rating = item.rating {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.48), in: Capsule())
                            }
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
    @State private var synopsisExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .bottomLeading) {
                    CachedPosterImage(
                        url: item.posterURL,
                        fallbackSymbol: item.symbol,
                        symbolSize: 92
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 370)
                    .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.05), location: 0),
                            .init(color: Color.cineNexBackground.opacity(0.28), location: 0.38),
                            .init(color: Color.cineNexBackground.opacity(0.98), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("CINENEX", systemImage: "play.rectangle.fill")
                                .font(.caption.weight(.heavy))
                                .tracking(1.3)
                                .foregroundStyle(Color.cineNexAccent)
                            Spacer()
                            Text(item.kind.rawValue.uppercased())
                                .font(.caption2.weight(.heavy))
                                .tracking(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.42), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                        }

                        Spacer(minLength: 72)

                        Text(item.title)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .tracking(-0.8)
                            .foregroundStyle(.white)
                            .lineLimit(3)
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
                                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.28))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)

                        if !item.runtime.isEmpty {
                            Label(item.runtime, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .padding(22)
                }
                .frame(height: 370)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if let tagline = extendedDetails?.tagline,
                       !tagline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(tagline)
                            .font(.subheadline.italic())
                            .foregroundStyle(Color.cineNexAccent)
                    }
                    HStack(spacing: 10) {
                        Button(action: onPlay) {
                            Label(item.streamURL == nil ? "Find sources" : "Play now", systemImage: item.streamURL == nil ? "dot.radiowaves.left.and.right" : "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint(item.streamURL == nil ? "Search built-in playback providers for this movie or series" : "Start playback")

                        Button(action: onFavoriteToggle) {
                            Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                                .font(.headline)
                                .frame(width: 54, height: 52)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(isFavorite ? "Remove from My List" : "Save to My List")
                    }


                    VStack(alignment: .leading, spacing: 8) {
                        Text("ABOUT THIS TITLE")
                            .font(.caption.weight(.heavy))
                            .tracking(1.1)
                            .foregroundStyle(Color.cineNexAccent)
                        Text(item.synopsis)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(synopsisExpanded ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.synopsis.count > 180 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    synopsisExpanded.toggle()
                                }
                            } label: {
                                Label(synopsisExpanded ? "Show less" : "Read full synopsis",
                                      systemImage: synopsisExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.cineNexAccent)
                        }
                    }

                    if item.streamURL == nil {
                        Label("No direct link is attached. Find sources opens automatic provider search and does not require a TMDB token.", systemImage: "dot.radiowaves.left.and.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

                if let sourceURL = item.streamURL {
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
