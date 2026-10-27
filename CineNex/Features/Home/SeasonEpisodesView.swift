import SwiftUI

struct SeasonEpisodesView: View {
    let item: MediaItem
    let season: TMDBTitleSeason

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("cinenex.reduceMotion") private var reduceMotion = false
    @AppStorage("cinenex.episodeNavigator.sort") private var storedSort = EpisodeNavigatorSort.firstToLast.rawValue
    @AppStorage("cinenex.episodeNavigator.hideSummaries") private var hideSummaries = false
    @ObservedObject private var history = EpisodeNavigatorHistory.shared
    @State private var watchRequest: EpisodeWatchRequest?
    @State private var pendingDirectPlayback: MediaItem?
    @State private var activeDirectPlayback: MediaItem?
    @State private var episodes: [TMDBSeasonEpisode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var statusFilter = EpisodeNavigatorFilter.all
    @State private var highlightedEpisodeID: Int?
    @State private var jumpTask: Task<Void, Never>?
    @State private var showingJump = false
    @State private var jumpNumber = ""
    @State private var jumpError: String?

    private var sort: EpisodeNavigatorSort {
        let value = EpisodeNavigatorSort(rawValue: storedSort) ?? .firstToLast
        return value == .highestRated && !canSortByRating ? .firstToLast : value
    }
    private var watchedNumbers: Set<Int> { history.numbers(itemID: item.id, season: season.seasonNumber) }
    private var visibleEpisodes: [TMDBSeasonEpisode] {
        EpisodeNavigatorPolicy.filtered(episodes, query: searchText, sort: sort, filter: statusFilter, watched: watchedNumbers)
    }
    private var nextEpisode: TMDBSeasonEpisode? { EpisodeNavigatorPolicy.nextUnwatched(episodes, watched: watchedNumbers) }
    private var markedCount: Int { episodes.filter { watchedNumbers.contains($0.episodeNumber) }.count }
    private var canSortByRating: Bool { episodes.contains { EpisodeNavigatorPolicy.validRating($0.voteAverage) != nil } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        seasonHeader
                        if isLoading {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Loading the episode guide").font(.headline)
                                ProgressView().progressViewStyle(.linear)
                                Text("Fetching episode names, stills and air dates from TMDB.").font(.caption).foregroundStyle(.secondary)
                            }.padding(18).background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if !episodes.isEmpty {
                            navigatorSummary(proxy: proxy)
                            episodeControls(proxy: proxy)
                        }
                        if let errorMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Episode guide unavailable", systemImage: "wifi.exclamationmark").font(.headline)
                                Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                                Button("Try again") { Task { await loadEpisodes() } }.buttonStyle(.borderedProminent)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if !isLoading && errorMessage == nil && episodes.isEmpty {
                            ContentUnavailableView("No episodes listed", systemImage: "rectangle.stack",
                                                   description: Text("TMDB has not provided an episode guide for this season."))
                        } else if !episodes.isEmpty && visibleEpisodes.isEmpty {
                            ContentUnavailableView {
                                Label("No matching episodes", systemImage: "magnifyingglass")
                            } description: {
                                Text("Try an episode title, number or a word from its summary.")
                            } actions: {
                                Button("Clear search and filters") { searchText = ""; statusFilter = .all }
                            }
                        }
                        ForEach(visibleEpisodes) { episode in
                            episodeCard(episode)
                                .id(episode.id)
                        }
                    }
                    .padding(20)
                }
                .refreshable { await loadEpisodes() }
                .background(Color.cineNexBackground)
                .navigationTitle(season.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Toggle("Hide episode summaries", isOn: $hideSummaries)
                            Button("Jump to episode", systemImage: "number") { jumpNumber = ""; jumpError = nil; showingJump = true }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Episode guide options")
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $showingJump) { jumpSheet(proxy: proxy) }
                .task(id: "\(item.id)-\(season.seasonNumber)") { await loadEpisodes() }
                .onDisappear { jumpTask?.cancel(); jumpTask = nil }
            }
        }
        .tint(Color.cineNexAccent)
        .sheet(item: $watchRequest, onDismiss: {
            if let pending = pendingDirectPlayback {
                pendingDirectPlayback = nil
                activeDirectPlayback = pending
            }
        }) { request in
            WatchHubView(
                item: request.item,
                onPlayDirect: { directItem in pendingDirectPlayback = directItem; watchRequest = nil },
                onSelectItem: { recommendation in
                    watchRequest = EpisodeWatchRequest(item: recommendation, seasonNumber: 1, episodeNumber: 1)
                },
                initialSeasonNumber: request.seasonNumber,
                initialEpisodeNumber: request.episodeNumber
            )
        }
        .fullScreenCover(item: $activeDirectPlayback) { directItem in
            PlayerView(item: directItem, progressStore: PlaybackProgressStore.shared)
        }
    }

    private var seasonHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            CachedPosterImage(url: season.posterURL ?? item.posterURL, fallbackSymbol: "tv", symbolSize: 32)
                .frame(width: 88, height: 132).clipShape(RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title).font(.caption.weight(.bold)).foregroundStyle(Color.cineNexAccent)
                Text(season.displayName).font(.title.bold())
                HStack(spacing: 12) {
                    if let year = season.airYear { Text(String(year)) }
                    if !episodes.isEmpty { Text("\(episodes.count) episodes") }
                    else if let count = season.episodeCount, count > 0 { Text("\(count) episodes") }
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
                    Text(overview).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }

    private func navigatorSummary(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Your episode guide", systemImage: "play.rectangle.on.rectangle").font(.headline)
                Spacer()
                Text("\(markedCount) / \(episodes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(markedCount), total: Double(max(1, episodes.count)))
                .tint(Color.cineNexAccent).accessibilityLabel("Episodes manually marked watched")
            if let nextEpisode {
                Button { jump(to: nextEpisode, proxy: proxy) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.turn.down.right").font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Next unwatched · E\(nextEpisode.episodeNumber)").font(.caption.weight(.semibold))
                            Text(nextEpisode.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).cineNexGlass(in: RoundedRectangle(cornerRadius: 16))
            } else if markedCount == episodes.count {
                Label("All listed episodes marked watched", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(Color.cineNexAccent)
            }
            Text("Watched marks are manual, saved on this device, and separate from connected account lists.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func episodeControls(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Title, episode number or summary", text: $searchText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit {
                        if let number = Int(searchText.trimmingCharacters(in: .whitespacesAndNewlines)),
                           let target = episodes.first(where: { $0.episodeNumber == number }) { jump(to: target, proxy: proxy) }
                    }
                    .accessibilityLabel("Search this season")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear episode search")
                }
            }.padding(14).background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 15))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { filterMenu; sortMenu; Spacer(minLength: 0); jumpButton }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { filterMenu; Spacer(); jumpButton }
                    sortMenu
                }
            }
            Text("Showing \(visibleEpisodes.count) of \(episodes.count) episodes · \(sort.title)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Watch status", selection: $statusFilter) {
                ForEach(EpisodeNavigatorFilter.allCases) { filter in Text(filter.title).tag(filter) }
            }
        } label: {
            Label(statusFilter.title, systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 10)
        }.cineNexGlass(in: Capsule())
    }
    private var sortMenu: some View {
        Menu {
            ForEach(EpisodeNavigatorSort.allCases.filter { $0 != .highestRated || canSortByRating }) { order in
                Button { storedSort = order.rawValue } label: {
                    if sort == order { Label(order.title, systemImage: "checkmark") } else { Text(order.title) }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 10)
        }.cineNexGlass(in: Capsule())
    }
    private var jumpButton: some View {
        Button { jumpNumber = ""; jumpError = nil; showingJump = true } label: {
            Label("Jump", systemImage: "number").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 10)
        }.buttonStyle(.plain).cineNexGlass(in: Capsule())
    }

    private func episodeCard(_ episode: TMDBSeasonEpisode) -> some View {
        let watched = watchedNumbers.contains(episode.episodeNumber)
        let upcoming = EpisodeNavigatorPolicy.validDate(episode.airDate).map { $0 > EpisodeNavigatorPolicy.utcToday() } ?? false
        return VStack(alignment: .leading, spacing: 0) {
            Button { open(episode) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    CachedPosterImage(url: episode.stillURL, fallbackSymbol: "play.rectangle", symbolSize: 38)
                        .frame(maxWidth: .infinity).frame(height: 170).clipped()
                        .overlay(alignment: .topLeading) {
                            Text("E\(episode.episodeNumber)").font(.caption.bold().monospacedDigit())
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .cineNexGlass(in: Capsule()).padding(12)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "play.fill").font(.headline).frame(width: 42, height: 42)
                                .cineNexGlass(in: Circle()).padding(12)
                        }
                    VStack(alignment: .leading, spacing: 10) {
                        highlightedText(episode.displayName).font(.title3.bold()).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            if let date = EpisodeNavigatorPolicy.validDate(episode.airDate) { Text(upcoming ? "Coming \(date)" : date) }
                            if let runtime = episode.runtimeLabel { Text(runtime) }
                            if let rating = EpisodeNavigatorPolicy.validRating(episode.voteAverage) {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        if !hideSummaries {
                            let overview = episode.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            highlightedText(overview.isEmpty ? "No episode summary available." : overview)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label("Find sources for this episode", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.cineNexAccent)
                    }.padding(16)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(episode.accessibilitySummary)
                .accessibilityHint("Find sources for this episode")
            Divider().overlay(.white.opacity(0.04))
            Button {
                history.setWatched(!watched, itemID: item.id, season: season.seasonNumber, episode: episode.episodeNumber)
            } label: {
                Label(watched ? "Marked watched · tap to undo" : "Mark as watched", systemImage: watched ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(watched ? Color.cineNexAccent : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 13)
            }.buttonStyle(.plain)
        }
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(highlightedEpisodeID == episode.id ? Color.cineNexAccent : Color.white.opacity(0.07), lineWidth: highlightedEpisodeID == episode.id ? 2 : 1))
    }

    private func highlightedText(_ value: String) -> Text {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, Int(query) == nil else { return Text(value) }
        var result = AttributedString(value)
        var searchRange = value.startIndex..<value.endIndex
        while let match = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange), !match.isEmpty {
            if let range = Range(match, in: result) {
                result[range].foregroundColor = Color.cineNexAccent
                result[range].inlinePresentationIntent = .stronglyEmphasized
            }
            searchRange = match.upperBound..<value.endIndex
        }
        return Text(result)
    }

    private func open(_ episode: TMDBSeasonEpisode) {
        watchRequest = EpisodeWatchRequest(item: item, seasonNumber: season.seasonNumber, episodeNumber: episode.episodeNumber)
    }
    private func jump(to episode: TMDBSeasonEpisode, proxy: ScrollViewProxy) {
        if !visibleEpisodes.contains(where: { $0.id == episode.id }) { searchText = ""; statusFilter = .all }
        showingJump = false
        jumpTask?.cancel()
        jumpTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 0.25)) {
                proxy.scrollTo(episode.id, anchor: .top)
                highlightedEpisodeID = episode.id
            }
            do { try await Task.sleep(for: .milliseconds(1_600)) } catch { return }
            guard !Task.isCancelled, highlightedEpisodeID == episode.id else { return }
            highlightedEpisodeID = nil
        }
    }

    private func jumpSheet(proxy: ScrollViewProxy) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Go directly to an episode, without changing the season.").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        TextField("Episode number", text: $jumpNumber).keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Episode number to jump to")
                            .onChange(of: jumpNumber) { _, value in jumpNumber = String(value.filter(\.isNumber).prefix(5)); jumpError = nil }
                        Button("Go") {
                            guard let number = Int(jumpNumber), let target = episodes.first(where: { $0.episodeNumber == number }) else {
                                jumpError = "Choose an episode number listed below."; return
                            }
                            jump(to: target, proxy: proxy)
                        }.buttonStyle(.borderedProminent)
                    }
                    if let jumpError { Text(jumpError).font(.caption).foregroundStyle(.orange) }
                    if let nextEpisode {
                        Button("Next unwatched · Episode \(nextEpisode.episodeNumber)") { jump(to: nextEpisode, proxy: proxy) }
                            .buttonStyle(.bordered)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                        ForEach(EpisodeNavigatorPolicy.filtered(episodes, query: "", sort: .firstToLast)) { episode in
                            Button { jump(to: episode, proxy: proxy) } label: {
                                VStack(spacing: 4) {
                                    Text(String(episode.episodeNumber)).font(.headline.monospacedDigit())
                                    if watchedNumbers.contains(episode.episodeNumber) { Image(systemName: "checkmark").font(.caption2) }
                                }.frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.plain).cineNexGlass(in: RoundedRectangle(cornerRadius: 13), prominent: nextEpisode?.id == episode.id)
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("Jump to episode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingJump = false } } }
        }.presentationDetents([.medium, .large])
    }

    @MainActor
    private func loadEpisodes() async {
        guard !isLoading else { return }
        guard let token = TMDBTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            errorMessage = "Connect TMDB in Settings → Accounts & tracking to view season episodes."; return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            episodes = try await TMDBCatalogProvider(readAccessToken: token).fetchSeasonEpisodes(for: item, seasonNumber: season.seasonNumber)
        } catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct EpisodeWatchRequest: Identifiable {
    let item: MediaItem
    let seasonNumber: Int
    let episodeNumber: Int
    var id: String { "\(item.id)-\(seasonNumber)-\(episodeNumber)" }
}
