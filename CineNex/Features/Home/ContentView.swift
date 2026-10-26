import SwiftUI

struct ContentView: View {
    @State private var selectedTab = AppTab.home
    @AppStorage("cinenex.accentPreset") private var accentPreset = "violet"
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

    @State private var showingDownloads = false
    @State private var libraryShowsProgress = false
    @State private var libraryQuery = ""
    @State private var pendingDirectPlayback: MediaItem?

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                    homeScreen
                }
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                    searchScreen
                }
                Tab("Library", systemImage: "bookmark.fill", value: AppTab.library) {
                    libraryScreen
                }
                Tab("Settings", systemImage: "gearshape.fill", value: AppTab.tracking) {
                    CineNexSettingsView()
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(
                    item: item,
                    isFavorite: favorites.contains(item.id),
                    onFavoriteToggle: { toggleFavorite(item) },
                    onPlay: { watchHubItem = item },
                    onSelectItem: { selectedItem = $0 }
                )
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == .home {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Search", systemImage: "magnifyingglass") { selectedTab = .search }
                    }
                }
            }
        }
        .tint(currentAccent)
        .preferredColorScheme(.dark)
        .task { await loadCatalog() }
        .task(id: selectedHomeExperience) {
            if selectedHomeExperience == "anime" { await loadAnimeCatalog() }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime, progressStore: animeProgressStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $watchHubItem, onDismiss: presentPendingDirectPlayback) { item in
            WatchHubView(item: item, onPlayDirect: { directItem in
                pendingDirectPlayback = directItem
                watchHubItem = nil
            }, onSelectItem: { watchHubItem = $0 })
        }
        .sheet(isPresented: $showingDownloads, onDismiss: presentPendingDirectPlayback) {
            NavigationStack {
                OfflineLibraryView { download, localURL in
                    pendingDirectPlayback = MediaItem(
                        id: "offline-\(download.id)", title: download.title, kind: .movie,
                        year: 0, genre: "Offline", synopsis: "Downloaded for offline playback.",
                        symbol: "arrow.down.circle.fill", runtime: "Offline media", streamURL: localURL
                    )
                    showingDownloads = false
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDownloads = false }
                    }
                }
            }
        }
        .fullScreenCover(item: $activePlayerItem) { item in
            PlayerView(item: item, progressStore: playbackProgressStore)
        }
    }

    private var currentAccent: Color {
        _ = accentPreset
        return Color.cineNexAccent
    }

    private var navigationTitle: String {
        switch selectedTab {
        case .home: return "CineNex"
        case .search: return "Search"
        case .library: return "Your library"
        case .tracking: return "Settings"
        }
    }

    private var experiencePicker: some View {
        Picker("Browse", selection: $selectedHomeExperience) {
            Text("Movies & series").tag("moviesAndSeries")
            Text("Anime").tag("anime")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var homeScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                experiencePicker
                if selectedHomeExperience == "anime" {
                    animeHomeContent
                } else {
                    moviesAndSeriesHomeContent
                }
            }
            .padding(.bottom, 30)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .refreshable {
            if selectedHomeExperience == "anime" { await loadAnimeCatalog(force: true) }
            else { await loadCatalog(force: true) }
        }
    }

    private var moviesAndSeriesHomeContent: some View {
        Group {
            if catalogLoading && catalog.isEmpty {
                ProgressView("Loading your next watch…")
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if catalog.isEmpty {
                ContentUnavailableView {
                    Label("Discover is unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(catalogError ?? "Pull down to reload the catalog.")
                } actions: {
                    Button("Try again") { Task { await loadCatalog(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                if !continueWatchingItems.isEmpty {
                    continueWatchingSection
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Featured").font(.title.bold())
                            Text("Movies and series to explore").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(.horizontal, 20)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(Array(catalog.prefix(5))) { item in
                                CatalogFeatureCard(item: item, saved: favorites.contains(item.id),
                                                   onDetails: { selectedItem = item },
                                                   onPlay: { watchHubItem = item },
                                                   onSave: { toggleFavorite(item) })
                                    .containerRelativeFrame(.horizontal) { width, _ in min(width - 40, 480) }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 20)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                }
                browseDestinations
                if let catalogError {
                    Label(catalogError, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                }
                let unwatched = favoriteItems.filter { playbackProgressStore.progress(for: $0.id) == nil }
                if !unwatched.isEmpty {
                    mediaSection(title: "Your watchlist", subtitle: "Saved for a night like this", items: unwatched)
                }
                let topRated = catalog.filter { ($0.rating ?? 0) >= 7 }.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
                if !topRated.isEmpty { mediaSection(title: "Highly rated", subtitle: "Standouts worth a closer look", items: Array(topRated.prefix(10))) }
                let movies = catalog.filter { $0.kind == .movie }
                if !movies.isEmpty { mediaSection(title: "Movie night", subtitle: "Find your next feature", items: movies) }
                let series = catalog.filter { $0.kind == .series }
                if !series.isEmpty { mediaSection(title: "One more episode", subtitle: "Series to spend time with", items: series) }
                genreDestinations
            }
        }
    }

    private var browseDestinations: some View {
        HStack(spacing: 12) {
            NavigationLink {
                catalogCollection(title: "Movies", items: catalog.filter { $0.kind == .movie })
            } label: {
                Label("All movies", systemImage: "film.stack")
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            NavigationLink {
                catalogCollection(title: "Series", items: catalog.filter { $0.kind == .series })
            } label: {
                Label("All series", systemImage: "tv")
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var catalogGenres: [String] {
        Array(Set(catalog.flatMap { $0.genre.components(separatedBy: CharacterSet(charactersIn: ",·/")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Unknown" })).sorted()
    }

    private var genreDestinations: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browse by genre").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(catalogGenres, id: \.self) { genre in
                    NavigationLink {
                        catalogCollection(title: genre, items: catalog.filter { $0.genre.localizedCaseInsensitiveContains(genre) })
                    } label: {
                        HStack {
                            Text(genre).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right").font(.caption)
                        }
                        .foregroundStyle(.primary)
                        .padding(18)
                        .background(Color.cineNexAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal, 20)
    }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Continue watching").font(.title2.bold())
                Spacer()
                Button("See all") {
                    libraryShowsProgress = true
                    selectedTab = .library
                }.font(.subheadline.weight(.semibold))
            }
            ForEach(Array(continueWatchingItems.prefix(2))) { item in
                CatalogLibraryRow(item: item, progress: playbackProgressStore.progress(for: item.id),
                                  onDetails: { selectedItem = item }, onPlay: { play(item) })
                    .contextMenu {
                        Button("Remove progress", systemImage: "xmark.circle", role: .destructive) {
                            playbackProgressStore.remove(itemID: item.id)
                        }
                    }
            }
        }.padding(.horizontal, 20)
    }

    private var animeHomeContent: some View {
        Group {
            if let animeError {
                Label(animeError, systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange).padding(.horizontal, 20)
            }
            if animeLoading && animeCatalog.isEmpty {
                ProgressView("Loading anime…").frame(maxWidth: .infinity, minHeight: 240)
            } else if animeCatalog.isEmpty {
                ContentUnavailableView("No anime available", systemImage: "sparkles.tv", description: Text("Pull down to try again."))
            } else {
                if let featured = animeCatalog.first {
                    AnimeFeaturedBanner(anime: featured) { selectedAnime = featured }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Trending anime").font(.title2.bold()).padding(.horizontal, 20)
                    AnimePosterShelf(items: animeCatalog, progressStore: animeProgressStore) { selectedAnime = $0 }
                }
            }
        }
    }

    private var searchBinding: Binding<String> {
        Binding(get: { selectedHomeExperience == "anime" ? animeSearchText : searchText },
                set: { if selectedHomeExperience == "anime" { animeSearchText = $0 } else { searchText = $0 } })
    }

    private var searchScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                experiencePicker
                if selectedHomeExperience == "anime" {
                    if animeSearchLoading { ProgressView("Searching anime…").frame(maxWidth: .infinity) }
                    if let animeSearchError { Text(animeSearchError).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 20) }
                    if animeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchPrompt
                    } else if hasSearchedAnime && animeSearchResults.isEmpty && !animeSearchLoading {
                        ContentUnavailableView.search(text: animeSearchText)
                    } else {
                        LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 22) {
                            ForEach(animeSearchResults) { anime in
                                AnimePosterCard(anime: anime, watchedEpisodes: animeProgressStore.watchedEpisodeCount(for: anime)) { selectedAnime = anime }
                            }
                        }.padding(.horizontal, 20)
                    }
                } else {
                    HStack {
                        Picker("Type", selection: $selectedSearchKind) {
                            ForEach(SearchKind.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        Menu {
                            Picker("Sort results", selection: $selectedSearchSort) {
                                ForEach(SearchSort.allCases) { Text($0.title).tag($0) }
                            }
                        } label: { Image(systemName: "line.3.horizontal.decrease").font(.title3) }
                        .accessibilityLabel("Sort results")
                    }.padding(.horizontal, 20)
                    if remoteSearchLoading { ProgressView("Searching…").frame(maxWidth: .infinity) }
                    if let remoteSearchError { Text(remoteSearchError).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 20) }
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchPrompt
                    } else if displayedSearchResults.isEmpty && !remoteSearchLoading {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        posterGrid(displayedSearchResults)
                        if remoteSearchPage < remoteSearchTotalPages {
                            Button(remoteSearchLoadingMore ? "Loading…" : "Load more results") {
                                Task { await loadMoreTMDBSearchResults() }
                            }
                            .disabled(remoteSearchLoadingMore)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }.padding(.bottom, 30)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .searchable(text: searchBinding, prompt: "Titles, movies, series, anime")
        .task(id: "\(selectedHomeExperience)|\(searchBinding.wrappedValue)") {
            guard selectedTab == .search else { return }
            let query = searchBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            if selectedHomeExperience == "anime" { await searchAniList() }
            else { await searchTMDB() }
        }
    }

    private var searchPrompt: some View {
        VStack(alignment: .leading, spacing: 24) {
            if selectedHomeExperience == "anime" {
                ContentUnavailableView("Find your next anime", systemImage: "sparkles.tv",
                                       description: Text("Search titles from AniList above."))
            } else {
                genreDestinations
                VStack(alignment: .leading, spacing: 8) {
                    Text("Popular titles").font(.title2.bold())
                    ForEach(Array(catalog.prefix(6))) { item in
                        CatalogLibraryRow(item: item, onDetails: { selectedItem = item }, onPlay: { watchHubItem = item })
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    private var libraryScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                experiencePicker
                Button { showingDownloads = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.circle.fill").font(.title)
                            .foregroundStyle(Color.cineNexAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Downloads").font(.headline)
                            Text("Available without a connection").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).padding(.horizontal, 20)
                if selectedHomeExperience == "anime" {
                    let saved = animeProgressStore.trackedAnime.filter { libraryQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(libraryQuery) }
                    if saved.isEmpty {
                        ContentUnavailableView("No anime in progress", systemImage: "play.circle", description: Text("Update the episode progress on an anime to find it here."))
                    } else {
                        LazyVGrid(columns: posterColumns, spacing: 22) {
                            ForEach(saved) { anime in
                                AnimePosterCard(anime: anime, watchedEpisodes: animeProgressStore.watchedEpisodeCount(for: anime)) { selectedAnime = anime }
                            }
                        }.padding(.horizontal, 20)
                    }
                } else {
                    Picker("Your library", selection: $libraryShowsProgress) {
                        Text("Watchlist").tag(false)
                        Text("Continue watching").tag(true)
                    }.pickerStyle(.segmented).padding(.horizontal, 20)
                    let sourceItems = libraryShowsProgress ? continueWatchingItems : favoriteItems.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    let items = sourceItems.filter { libraryQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(libraryQuery) }
                    if items.isEmpty {
                        if !libraryQuery.isEmpty {
                            ContentUnavailableView.search(text: libraryQuery)
                            Button("Clear search") { libraryQuery = "" }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        } else {
                            ContentUnavailableView(libraryShowsProgress ? "Nothing in progress" : "Your watchlist is empty",
                                                   systemImage: libraryShowsProgress ? "play.circle" : "bookmark",
                                                   description: Text(libraryShowsProgress ? "Started movies appear here so you can resume them." : "Save a title from its details to find it here."))
                            Button("Discover something new") { selectedTab = .home }
                                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(items.count) titles").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                            ForEach(items) { item in
                                CatalogLibraryRow(item: item,
                                                  progress: libraryShowsProgress ? playbackProgressStore.progress(for: item.id) : nil,
                                                  onDetails: { selectedItem = item }, onPlay: { play(item) })
                                    .contextMenu {
                                        if libraryShowsProgress {
                                            Button("Remove progress", systemImage: "xmark.circle", role: .destructive) {
                                                playbackProgressStore.remove(itemID: item.id)
                                            }
                                        } else {
                                            Button("Remove from watchlist", systemImage: "bookmark.slash", role: .destructive) {
                                                toggleFavorite(item)
                                            }
                                        }
                                    }
                                Divider().opacity(0.35)
                            }
                        }.padding(.horizontal, 20)
                    }
                }
            }.padding(.bottom, 30)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .searchable(text: $libraryQuery, prompt: "Search your library")
    }

    private var posterColumns: [GridItem] { [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)] }

    private func posterGrid(_ items: [MediaItem]) -> some View {
        LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 24) {
            ForEach(items) { item in
                MediaPosterCard(item: item) { selectedItem = item }
                    .contextMenu {
                        Button(favorites.contains(item.id) ? "Remove from watchlist" : "Save to watchlist",
                               systemImage: favorites.contains(item.id) ? "bookmark.slash" : "bookmark") { toggleFavorite(item) }
                    }
            }
        }.padding(.horizontal, 20)
    }

    private func catalogCollection(title: String, items: [MediaItem]) -> some View {
        CatalogBrowserView(title: title, items: items) { selectedItem = $0 }
    }

    private func mediaSection(title: String, subtitle: String, items: [MediaItem], showProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                NavigationLink { catalogCollection(title: title, items: items) } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }.font(.subheadline.weight(.semibold))
                }.accessibilityLabel("See all \(title)")
            }.padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(items.prefix(20))) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            MediaPosterCard(item: item) { selectedItem = item }.frame(width: 148)
                            if showProgress, let progress = playbackProgressStore.progress(for: item.id) {
                                ProgressView(value: progress.completionFraction ?? 0).tint(Color.cineNexAccent)
                                Button {
                                    play(item)
                                } label: {
                                    Label("Resume · \(Int(progress.position / 60)) min", systemImage: "play.fill")
                                        .font(.caption.weight(.semibold))
                                }.buttonStyle(.plain)
                            }
                        }
                        .frame(width: 148)
                        .contextMenu {
                            if showProgress {
                                Button("Remove from continue watching", systemImage: "xmark.circle", role: .destructive) {
                                    playbackProgressStore.remove(itemID: item.id)
                                }
                            } else {
                                Button(favorites.contains(item.id) ? "Remove from watchlist" : "Save to watchlist",
                                       systemImage: "bookmark") { toggleFavorite(item) }
                            }
                        }
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
    }

    private func presentPendingDirectPlayback() {
        guard let pending = pendingDirectPlayback else { return }
        pendingDirectPlayback = nil
        activePlayerItem = pending
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
                catalogError = "No titles were returned. Showing the last saved catalog."
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

private struct MediaPosterCard: View {
    let item: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) { CatalogPosterTile(item: item) }
            .buttonStyle(.plain)
            .accessibilityLabel(item.accessibilitySummary)
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
                HStack(alignment: .top, spacing: 20) {
                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 42)
                        .frame(width: 132, height: 198)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.kind.rawValue.uppercased()).font(.caption2.weight(.bold)).tracking(1.7)
                            .foregroundStyle(Color.cineNexAccent)
                        Text(item.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text([item.yearLabel, item.runtime.isEmpty ? nil : item.runtime].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let rating = item.rating, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
                        }
                        Text(item.genre).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 12) {
                    if let tagline = extendedDetails?.tagline,
                       !tagline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(tagline)
                            .font(.subheadline.italic())
                            .foregroundStyle(Color.cineNexAccent)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Story")
                            .font(.title3.bold())
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
                        Text("Details")
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
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { detailActions }
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

    private var detailActions: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label(item.kind == .series ? "Choose episode & watch" : "Watch movie", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.cineNexAccent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                    .font(.title3)
                    .frame(width: 54, height: 52)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel(isFavorite ? "Remove from watchlist" : "Save to watchlist")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
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
