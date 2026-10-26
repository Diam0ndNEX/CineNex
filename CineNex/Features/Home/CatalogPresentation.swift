import SwiftUI

/// Reuses SceneBox's poster shelves and searchable collection flow with CineNex metadata.
struct CatalogPosterTile: View {
    let item: MediaItem

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
                if let rating = item.rating, rating > 0 {
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

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Button(action: onDetails) {
                CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 32)
                    .frame(width: 112, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Details for \(item.title)")
            VStack(alignment: .leading, spacing: 10) {
                Text(item.kind.rawValue.uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(Color.cineNexAccent)
                Button(action: onDetails) {
                    Text(item.title).font(.title3.bold()).foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Text([item.yearLabel, item.genre].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(item.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Watch", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.cineNexAccent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Button(action: onSave) {
                        Image(systemName: saved ? "checkmark" : "plus")
                            .font(.subheadline.bold()).frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }.accessibilityLabel(saved ? "Remove from watchlist" : "Add to watchlist")
                }.padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
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
    @State private var query = ""
    @State private var sort = CatalogCollectionSort.relevance
    @State private var selectedGenre = ""

    private var genres: [String] {
        Array(Set(items.flatMap { $0.genre.components(separatedBy: CharacterSet(charactersIn: ",·/")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private var results: [MediaItem] {
        let matches = items.filter { item in
            (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)) &&
            (selectedGenre.isEmpty || item.genre.localizedCaseInsensitiveContains(selectedGenre))
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
                HStack {
                    Text("\(results.count) titles").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Genre", selection: $selectedGenre) {
                            Text("All genres").tag("")
                            ForEach(genres, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Sort", selection: $sort) {
                            ForEach(CatalogCollectionSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label("Filter & sort", systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if !selectedGenre.isEmpty {
                    Button { selectedGenre = "" } label: {
                        Label(selectedGenre, systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                }
                if results.isEmpty {
                    ContentUnavailableView("No matching titles", systemImage: "film.stack",
                                           description: Text("Try another title or clear the genre filter."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(results) { item in
                            Button { onSelect(item) } label: { CatalogPosterTile(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Filter these titles")
    }
}

private enum CatalogCollectionSort: String, CaseIterable, Identifiable {
    case relevance = "Original order"
    case newest = "Newest first"
    case rating = "Highest rated"
    case title = "Title A–Z"
    var id: String { rawValue }
}
