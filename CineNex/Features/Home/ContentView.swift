import SwiftUI

struct ContentView: View {
    @State private var selectedTab = AppTab.home
    @AppStorage("cinenex.accentPreset") private var accentPreset = "violet"
    @AppStorage("cinenex.canvasStyle") private var canvasStyle = "midnight"
    @AppStorage("cinenex.posterDensity") private var posterDensity = "comfortable"
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @AppStorage("cinenex.reduceMotion") private var reduceMotion = false
    @AppStorage("cinenex.recentSearches.v1") private var recentSearchesStorage = "[]"
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var homeLane = HomeDiscoveryLane.all
    @State private var libraryKind = SearchKind.all
    @State private var librarySort = SearchSort.title
    @State private var shuffleOffset = 0
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
    @State private var animeSearchGeneration = UUID()
    @State private var animeSearchError: String?
    @State private var hasSearchedAnime = false
    @StateObject private var animeProgressStore = AnimeProgressStore.shared

    @State private var catalog = CatalogCacheStore.shared.load()?.items ?? []
    @State private var catalogLoading = false
    @State private var catalogLoadStage = 0
    @State private var catalogPage = 0
    @State private var catalogTotalPages = 0
    @State private var catalogLoadingMore = false
    @State private var catalogMoreError: String?
    @State private var catalogGeneration = UUID()
    @State private var catalogPagingToken: String?
    @State private var catalogPaginationTask: Task<Void, Never>?
    @State private var latestCatalogPageItems: [MediaItem] = []
    @State private var animeLoadStage = 0
    @State private var catalogError: String?
    @State private var remoteSearchResults: [MediaItem] = []
    @State private var remoteSearchQuery = ""
    @State private var remoteSearchPage = 0
    @State private var remoteSearchTotalPages = 0
    @State private var remoteSearchLoading = false
    @State private var remoteSearchGeneration = UUID()
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
                Tab("Browse", systemImage: "square.grid.2x2.fill", value: AppTab.browse) {
                    CatalogBrowserView(title: "Browse", items: catalog, onSelect: { selectedItem = $0 },
                                       footer: AnyView(catalogPaginationFooter))
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
        _ = canvasStyle
        return Color.cineNexAccent
    }

    private var navigationTitle: String {
        switch selectedTab {
        case .home: return "CineNex"
        case .browse: return "Browse"
        case .search: return "Search"
        case .library: return "Your library"
        case .tracking: return "Settings"
        }
    }

    private var experiencePicker: some View {
        CineNexGlassGroup(spacing: 4) {
            HStack(spacing: 4) {
                experienceButton("Cinema", subtitle: "Movies & series", symbol: "film.stack", value: "moviesAndSeries")
                experienceButton("Anime", subtitle: "A different universe", symbol: "sparkles.tv", value: "anime")
            }
        }
        .padding(5)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func experienceButton(_ title: String, subtitle: String, symbol: String, value: String) -> some View {
        let selected = selectedHomeExperience == value
        return Button {
            if reduceMotion || systemReduceMotion { selectedHomeExperience = value }
            else { withAnimation(.easeInOut(duration: 0.2)) { selectedHomeExperience = value } }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle).font(.system(size: 9, weight: .medium)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(selected ? Color.cineNexAccent : Color.primary)
            .cineNexGlass(in: RoundedRectangle(cornerRadius: 16), prominent: selected)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Color.cineNexAccent.opacity(0.5) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == "anime" ? "Browse anime" : "Browse movies and series")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("browse.\(value)")
    }

    private var homeScreen: some View {
        VStack(spacing: 0) {
            experiencePicker
                .background(Color.cineNexBackground)
                .zIndex(1)
            Divider().opacity(0.25)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if selectedHomeExperience == "anime" {
                        if animeLoading && !animeCatalog.isEmpty { animeLoadingStatus }
                        animeHomeContent
                    } else {
                        if catalogLoading && !catalog.isEmpty { catalogLoadingStatus }
                        moviesAndSeriesHomeContent
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .refreshable {
                if selectedHomeExperience == "anime" { await loadAnimeCatalog(force: true) }
                else { await loadCatalog(force: true) }
            }
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
    }

    private var catalogLoadingStatus: some View {
        CatalogLoadingStatus(title: catalog.isEmpty ? "Loading movies & series" : "Refreshing movies & series",
                             stage: catalogLoadStage,
                             stages: ["Preparing catalog request", "Waiting for catalog metadata", "Saving catalog", "Catalog ready"])
            .padding(.horizontal, 20)
    }

    private var animeLoadingStatus: some View {
        CatalogLoadingStatus(title: animeCatalog.isEmpty ? "Loading anime" : "Refreshing anime",
                             stage: animeLoadStage,
                             stages: ["Preparing AniList request", "Waiting for anime metadata", "Preparing anime catalog", "Anime ready"])
            .padding(.horizontal, 20)
    }

    private var moviesAndSeriesHomeContent: some View {
        Group {
            if catalogLoading && catalog.isEmpty {
                catalogLoadingStatus
                    .padding(.vertical, 32)
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
                homeEditorialHeader
                homeLanePicker
                if homeLaneItems.isEmpty {
                    ContentUnavailableView("No titles in this lane", systemImage: "film.stack",
                                           description: Text(homeLane == .saved ? "Add titles to your watchlist to see them here." : "Try another lane or refresh the catalog."))
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(featuredLaneItems) { item in
                                CatalogFeatureCard(item: item, saved: favorites.contains(item.id),
                                                   onDetails: { selectedItem = item },
                                                   onPlay: { watchHubItem = item },
                                                   onSave: { toggleFavorite(item) })
                                    .containerRelativeFrame(.horizontal) { width, _ in min(width - 40, 500) }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 20)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    if homeLane != .all {
                        mediaSection(title: homeLane.rawValue, subtitle: "\(homeLaneItems.count) titles to explore", items: homeLaneItems)
                    }
                }
                browseDestinations
                if let catalogError {
                    Label(catalogError, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                }
                if homeLane == .all {
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
                let laneIDs = Set(homeLaneItems.map(\.id))
                let newlyLoaded = latestCatalogPageItems.filter { laneIDs.contains($0.id) }
                if !newlyLoaded.isEmpty {
                    mediaSection(title: "More discoveries", subtitle: "From the page you just loaded", items: newlyLoaded)
                }
                catalogPaginationFooter
            }
        }
    }

    @ViewBuilder
    private var catalogPaginationFooter: some View {
        if catalogPage > 0 && catalogPage < catalogTotalPages {
            CatalogAutomaticPageFooter(loadedCount: catalog.count, isLoading: catalogLoadingMore || catalogLoading,
                                       error: catalogMoreError) {
                guard !catalogLoading, !catalogLoadingMore else { return }
                catalogPaginationTask = Task { await loadMoreCatalog() }
            }
            .padding(.horizontal, 20)
        } else if catalogLoading {
            catalogLoadingStatus
        } else {
            Text("\(catalog.count) titles loaded")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(20)
        }
    }

    private var homeLaneItems: [MediaItem] {
        switch homeLane {
        case .all: return catalog
        case .movies: return catalog.filter { $0.kind == .movie }
        case .series: return catalog.filter { $0.kind == .series }
        case .rated: return catalog.filter { ($0.rating ?? 0) >= 7 }.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .recent: return catalog.sorted { $0.year == $1.year ? $0.title < $1.title : $0.year > $1.year }
        case .saved: return favoriteItems
        }
    }

    private var featuredLaneItems: [MediaItem] {
        let items = homeLaneItems
        guard !items.isEmpty else { return [] }
        let offset = shuffleOffset % items.count
        return Array((Array(items[offset...]) + Array(items[..<offset])).prefix(5))
    }

    private var homeEditorialHeader: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THE CINENEX EDIT").font(.system(size: 10, weight: .heavy)).tracking(2.4)
                    .foregroundStyle(Color.cineNexAccent)
                Text(homeLane == .all ? "Make tonight\na good watch." : homeLane.rawValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(catalog.count) titles in your discovery catalog")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                guard let item = homeLaneItems.randomElement() else { return }
                selectedItem = item
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "shuffle").font(.title2)
                    Text("Surprise me").font(.system(size: 9, weight: .bold))
                }
                .frame(width: 82, height: 82)
                .background(Color.cineNexAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.cineNexAccent.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(homeLaneItems.isEmpty)
        }.padding(.horizontal, 20)
    }

    private var homeLanePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(HomeDiscoveryLane.allCases) { lane in
                    Button {
                        homeLane = lane
                        shuffleOffset = 0
                    } label: {
                        Text(lane.rawValue).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .foregroundStyle(homeLane == lane ? Color.cineNexAccent : Color.primary)
                            .cineNexGlass(in: Capsule(), prominent: homeLane == lane)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(homeLane == lane ? .isSelected : [])
                    .accessibilityIdentifier("home.lane.\(lane.id)")
                }
                Button { shuffleOffset += 1 } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").frame(width: 42, height: 42)
                        .cineNexGlass(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Rotate featured picks")
            }.padding(.horizontal, 20)
        }.scrollIndicators(.hidden)
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
                animeLoadingStatus.padding(.vertical, 32)
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
                            CatalogAutomaticPageFooter(loadedCount: remoteSearchResults.count,
                                                       isLoading: remoteSearchLoading || remoteSearchLoadingMore,
                                                       error: remoteSearchError) {
                                Task { await loadMoreTMDBSearchResults() }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }.padding(.bottom, 30)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .searchable(text: searchBinding, prompt: "Find a title, a world, a new favorite")
        .onSubmit(of: .search) { rememberSearch(searchBinding.wrappedValue) }
        .task(id: "\(selectedTab == .search)|\(selectedHomeExperience)|\(searchBinding.wrappedValue)") {
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
            if recentSearches.isEmpty {
                ContentUnavailableView(selectedHomeExperience == "anime" ? "Search anime" : "Search movies & series",
                                       systemImage: "magnifyingglass",
                                       description: Text("Enter a title above. Your submitted searches will be saved here."))
            } else {
                recentSearchSection
            }
        }
    }

    private var recentSearches: [String] {
        guard let data = recentSearchesStorage.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(8))
    }

    private func rememberSearch(_ value: String) {
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        let values = [query] + recentSearches.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        if let data = try? JSONEncoder().encode(Array(values.prefix(8))), let json = String(data: data, encoding: .utf8) {
            recentSearchesStorage = json
        }
    }

    @ViewBuilder
    private var recentSearchSection: some View {
        if !recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Pick up a search").font(.title2.bold())
                    Spacer()
                    Button("Clear") { recentSearchesStorage = "[]" }.font(.caption.weight(.semibold))
                }
                ForEach(recentSearches, id: \.self) { query in
                    Button {
                        searchBinding.wrappedValue = query
                        rememberSearch(query)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.cineNexAccent)
                            Text(query).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                        }.font(.subheadline).padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20)
        }
    }

    private var libraryScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                experiencePicker
                libraryOverview
                Button { showingDownloads = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Color.cineNexAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your offline collection").font(.headline)
                            Text("Open downloads").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 20))
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
                    HStack {
                        Text(libraryShowsProgress ? "IN PROGRESS" : "SAVED FOR LATER")
                            .font(.system(size: 10, weight: .heavy)).tracking(1.6).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Picker("Type", selection: $libraryKind) {
                                ForEach(SearchKind.allCases) { Text($0.title).tag($0) }
                            }
                            Picker("Sort", selection: $librarySort) {
                                ForEach(SearchSort.allCases) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease").font(.caption.weight(.semibold))
                        }
                    }.padding(.horizontal, 20)
                    let items = libraryItems
                    if items.isEmpty {
                        if !libraryQuery.isEmpty || libraryKind != .all {
                            ContentUnavailableView("No matching titles", systemImage: "line.3.horizontal.decrease",
                                                   description: Text("Try another search or clear the type filter."))
                            Button("Clear filters") { libraryQuery = ""; libraryKind = .all }
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

    private var libraryItems: [MediaItem] {
        let source = libraryShowsProgress ? continueWatchingItems : favoriteItems
        let filtered = source.filter { item in
            let matchesKind = libraryKind == .all || (libraryKind == .movies && item.kind == .movie) || (libraryKind == .series && item.kind == .series)
            return matchesKind && (libraryQuery.isEmpty || item.title.localizedCaseInsensitiveContains(libraryQuery))
        }
        switch librarySort {
        case .relevance: return filtered
        case .title: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .newest: return filtered.sorted { $0.year == $1.year ? $0.title < $1.title : $0.year > $1.year }
        case .highestRated: return filtered.sorted { ($0.rating ?? 0) == ($1.rating ?? 0) ? $0.title < $1.title : ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }

    private var libraryOverview: some View {
        HStack(spacing: 12) {
            Button { libraryShowsProgress = false } label: {
                libraryMetric(title: "Watchlist", value: favoriteItems.count, symbol: "bookmark.fill", selected: !libraryShowsProgress)
            }
            Button { libraryShowsProgress = true } label: {
                libraryMetric(title: "In progress", value: continueWatchingItems.count, symbol: "play.circle.fill", selected: libraryShowsProgress)
            }
        }.buttonStyle(.plain).padding(.horizontal, 20)
    }

    private func libraryMetric(title: String, value: Int, symbol: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).foregroundStyle(Color.cineNexAccent)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "arrow.up.right").font(.caption)
                    .foregroundStyle(selected ? Color.cineNexAccent : Color.secondary)
            }
            Text(String(value)).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(selected ? Color.cineNexAccent.opacity(0.12) : Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? Color.cineNexAccent.opacity(0.35) : Color.clear, lineWidth: 1))
    }

    private var posterColumns: [GridItem] { [GridItem(.adaptive(minimum: posterDensity == "compact" ? 104 : 140), spacing: 16, alignment: .top)] }

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
        CatalogBrowserView(title: title, items: items, onSelect: { selectedItem = $0 })
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
        let generation = UUID()
        animeSearchGeneration = generation
        animeSearchLoading = true
        animeSearchError = nil
        hasSearchedAnime = true
        defer { if animeSearchGeneration == generation { animeSearchLoading = false } }

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
        animeLoadStage = 0
        animeError = nil
        defer { animeLoading = false }

        do {
            animeLoadStage = 1
            let results = try await AniListCatalogProvider().fetchTrending()
            guard !Task.isCancelled else { return }
            animeLoadStage = 2
            animeCatalog = results
            animeLoadStage = 3
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
        guard !catalogLoading else { return }
        if catalogLoadingMore && !force { return }
        catalogPaginationTask?.cancel()
        catalogPaginationTask = nil
        let generation = UUID()
        catalogGeneration = generation
        catalogLoadingMore = false
        catalogMoreError = nil
        let token = TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        catalogLoading = true
        catalogLoadStage = 0
        defer {
            if catalogGeneration == generation { catalogLoading = false }
        }
        do {
            let liveCatalog: [MediaItem]
            let pageNumber: Int
            let totalPages: Int
            catalogLoadStage = 1
            if token.isEmpty {
                liveCatalog = try await CinemetaCatalogProvider().fetchCatalog()
                pageNumber = 0
                totalPages = 0
            } else {
                let page = try await TMDBCatalogProvider(readAccessToken: token).catalogPage(page: 1)
                liveCatalog = page.items
                pageNumber = page.page
                totalPages = page.totalPages
            }
            guard !Task.isCancelled, catalogGeneration == generation else { return }
            guard !liveCatalog.isEmpty else {
                catalogError = "No titles were returned. Showing the last saved catalog."
                return
            }
            catalogLoadStage = 2
            var seenIDs = Set<String>()
            let uniqueCatalog = liveCatalog.filter { seenIDs.insert($0.id).inserted }
            catalog = uniqueCatalog
            latestCatalogPageItems = []
            catalogPage = pageNumber
            catalogTotalPages = totalPages
            catalogPagingToken = token.isEmpty ? nil : token
            // Cache only the refreshed first page, not an ever-growing browsing session.
            CatalogCacheStore.shared.save(uniqueCatalog)
            catalogLoadStage = 3
            catalogError = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, catalogGeneration == generation else { return }
            catalogError = error.localizedDescription
            if catalog.isEmpty { catalog = CatalogCacheStore.shared.load()?.items ?? [] }
        }
    }

    @MainActor
    private func loadMoreCatalog() async {
        guard !catalogLoading, !catalogLoadingMore, catalogPage > 0,
              catalogPage < catalogTotalPages, let token = catalogPagingToken else { return }
        guard TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines) == token else {
            catalogMoreError = "Your catalog connection changed. Pull down to refresh before loading more."
            return
        }
        let generation = catalogGeneration
        let nextPage = catalogPage + 1
        catalogLoadingMore = true
        catalogMoreError = nil
        defer {
            if catalogGeneration == generation {
                catalogLoadingMore = false
                catalogPaginationTask = nil
            }
        }
        do {
            let page = try await TMDBCatalogProvider(readAccessToken: token).catalogPage(page: nextPage)
            guard !Task.isCancelled, catalogGeneration == generation, !catalogLoading else { return }
            guard TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines) == token else {
                catalogMoreError = "Your catalog connection changed. Pull down to refresh."
                return
            }
            guard page.page == nextPage else {
                catalogMoreError = "The catalog returned an unexpected page. Pull down to refresh."
                return
            }
            var seenIDs = Set(catalog.map(\.id))
            let additions = page.items.filter { seenIDs.insert($0.id).inserted }
            catalog.append(contentsOf: additions)
            latestCatalogPageItems = additions
            catalogPage = page.page
            catalogTotalPages = page.totalPages
            if additions.isEmpty && page.hasMorePages {
                catalogMoreError = "No new titles on this page. You can load the next page to continue."
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, catalogGeneration == generation else { return }
            catalogMoreError = error.localizedDescription
        }
    }

    @MainActor
    private func searchTMDB() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let token = TMDBTokenStore.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generation = UUID()
        remoteSearchGeneration = generation
        remoteSearchLoading = true
        remoteSearchError = nil
        defer { if remoteSearchGeneration == generation { remoteSearchLoading = false } }
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
            guard !Task.isCancelled, remoteSearchGeneration == generation else { return }
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
    case browse
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
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @AppStorage("cinenex.reduceMotion") private var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CatalogDetailHero(item: item)

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
                                if reduceMotion || systemReduceMotion { synopsisExpanded.toggle() }
                                else { withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() } }
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
                        Text("At a glance")
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
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Seasons & episodes").font(.title3.bold())
                                Spacer()
                                Text("\(details.seasonSummaries.count) seasons").font(.caption).foregroundStyle(.secondary)
                            }
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(details.seasonSummaries) { season in
                                        Button { selectedSeason = season } label: {
                                            VStack(alignment: .leading, spacing: 9) {
                                                ZStack(alignment: .bottomTrailing) {
                                                    CachedPosterImage(url: season.posterURL, fallbackSymbol: "tv", symbolSize: 30)
                                                        .frame(width: 134, height: 186)
                                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                                    Image(systemName: "play.circle.fill").font(.title)
                                                        .foregroundStyle(.white).shadow(radius: 5).padding(9)
                                                }
                                                Text(season.displayName).font(.subheadline.bold()).lineLimit(1)
                                                if let count = season.episodeCount, count > 0 {
                                                    Text("\(count) episodes").font(.caption).foregroundStyle(.secondary)
                                                }
                                            }.frame(width: 134, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Browse and play episodes in \(season.displayName)")
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                    }

                    if !details.castMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Cast").font(.title3.bold())
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(castPresentations(details.castMembers)) { member in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Image(systemName: "person.crop.circle.fill").font(.system(size: 30))
                                                .foregroundStyle(Color.cineNexAccent.opacity(0.7))
                                            Text(member.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            Text(member.character).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        .frame(width: 132, alignment: .leading)
                                        .padding(14)
                                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
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

    private func castPresentations(_ cast: [TMDBTitleCastMember]) -> [DetailCastPresentation] {
        var seen = Set<String>()
        return cast.compactMap { member in
            let name = member.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let character = member.character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let id = "\(member.id.map(String.init) ?? name)|\(character)"
            guard seen.insert(id).inserted else { return nil }
            return DetailCastPresentation(id: id, name: name, character: character)
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

private enum HomeDiscoveryLane: String, CaseIterable, Identifiable {
    case all = "For you"
    case movies = "Movies"
    case series = "Series"
    case rated = "Top rated"
    case recent = "Newest"
    case saved = "Watchlist"
    var id: String { rawValue }
}

private struct DetailCastPresentation: Identifiable {
    let id: String
    let name: String
    let character: String
}
