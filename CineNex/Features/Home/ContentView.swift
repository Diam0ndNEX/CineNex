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

    private let catalog = MediaItem.demoCatalog

    private var filteredCatalog: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalog }
        return catalog.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.genre.localizedCaseInsensitiveContains(query)
                || $0.kind.rawValue.localizedCaseInsensitiveContains(query)
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

                if filteredCatalog.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(filteredCatalog) { item in
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

private extension Color {
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
                    Image(systemName: item.symbol)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
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
                    Image(systemName: item.symbol)
                        .font(.system(size: 88, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(height: 280)

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.largeTitle.bold())
                    Text("\(item.year)  •  \(item.kind.rawValue)  •  \(item.genre)  •  \(item.runtime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
