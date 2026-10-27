import SwiftUI

/// A collection owns its network query and cursor; it never filters a fixed global trending snapshot.
@MainActor
struct GenreCatalogView: View {
    let title: String
    let genre: String?
    let kind: MediaKind?
    let order: GenreCatalogOrder
    let onSelect: (MediaItem) -> Void
    @StateObject private var model: GenreCatalogModel
    @State private var selectedKind: MediaKind?
    @State private var footerVisible = false
    @State private var pagingTask: Task<Void, Never>?
    @AppStorage("cinenex.posterColumns") private var posterColumns = 3

    init(title: String, genre: String? = nil, kind: MediaKind? = nil, order: GenreCatalogOrder = .popular, seedItems: [MediaItem], onSelect: @escaping (MediaItem) -> Void) {
        self.title = title
        self.genre = genre
        self.kind = kind
        self.order = order
        self.onSelect = onSelect
        _selectedKind = State(initialValue: kind)
        let query = GenreCatalogQuery(genre: genre, kind: kind, order: order)
        _model = StateObject(wrappedValue: GenreCatalogModel(query: query, seedItems: seedItems,
                                                            provider: DeferredGenreCatalogProvider()))
    }
    private var requestQuery: GenreCatalogQuery { GenreCatalogQuery(genre: genre, kind: kind ?? selectedKind, order: order) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: min(4, max(2, posterColumns)))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if let genre { Text(genre).foregroundStyle(Color.cineNexAccent) }
                        Text(requestQuery.kind?.rawValue ?? "Movies & series").foregroundStyle(.secondary)
                        Text("· \(model.items.count) titles").foregroundStyle(.secondary)
                    }.font(.caption.weight(.semibold))
                    Text("New pages load as you browse.").font(.subheadline).foregroundStyle(.secondary)
                }
                if kind == nil {
                    Picker("Content type", selection: $selectedKind) {
                        Text("All").tag(Optional<MediaKind>.none)
                        Text("Movies").tag(Optional(MediaKind.movie))
                        Text("Series").tag(Optional(MediaKind.series))
                    }.pickerStyle(.segmented)
                }
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView("No titles returned", systemImage: "rectangle.stack",
                                           description: Text("The provider has no matching titles for this collection."))
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(model.items) { item in
                        Button { onSelect(item) } label: { CatalogPosterTile(item: item) }
                            .buttonStyle(.plain).accessibilityLabel(item.accessibilitySummary)
                            .accessibilityIdentifier("title.\(item.id)")
                    }
                }
                paginationFooter
                    .onAppear { footerVisible = true; startPagingIfNeeded() }
                    .onDisappear { footerVisible = false }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Color.cineNexBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable {
            pagingTask?.cancel()
            await model.reload(query: requestQuery)
        }
        .task(id: requestQuery) {
            pagingTask?.cancel()
            await model.ensureLoaded(query: requestQuery)
            startPagingIfNeeded()
        }
        .onChange(of: model.isLoading) { _, loading in
            if !loading { startPagingIfNeeded() }
        }
        .onDisappear {
            pagingTask?.cancel()
            pagingTask = nil
            model.invalidate()
        }
    }

    private var paginationFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isLoading {
                ProgressView().progressViewStyle(.linear).tint(Color.cineNexAccent)
                Text(model.pagesLoaded == 0 ? "Loading this collection…" : "Fetching the next page…")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let error = model.errorMessage {
                Label(error, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(.secondary)
                Button("Retry loading") { startPagingIfNeeded(force: true) }.buttonStyle(.bordered)
            } else if model.autoFillPaused {
                Text("The provider returned several pages without new matching titles. Continue to check the next pages.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Continue browsing") { startPagingIfNeeded(force: true) }.buttonStyle(.bordered)
            } else if model.hasMore {
                // A persistent sentinel: loading completion checks visibility again, so short
                // pages fill the viewport even when this footer never leaves the screen.
                Text("Keep browsing for more titles").font(.caption).foregroundStyle(.secondary)
            } else if !model.items.isEmpty {
                Label("You’ve reached the end of this collection", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func startPagingIfNeeded(force: Bool = false) {
        guard !model.isLoading, model.hasMore,
              force || (footerVisible && model.pagesLoaded > 0 && model.errorMessage == nil && !model.autoFillPaused) else { return }
        pagingTask?.cancel()
        pagingTask = Task { await model.loadMore() }
    }
}
