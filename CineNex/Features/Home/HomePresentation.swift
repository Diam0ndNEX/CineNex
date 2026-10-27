import SwiftUI

/// Original SwiftUI pager inspired by the supplied reference's home hero and layout options.
/// Selection follows stable title IDs through catalog refreshes; advancement is user initiated.
enum HomeHeroPaging {
    static func reconciledID(_ selectedID: String, in ids: [String]) -> String {
        ids.contains(selectedID) ? selectedID : (ids.first ?? "")
    }

    static func adjacentID(to selectedID: String, in ids: [String], forward: Bool) -> String? {
        guard !ids.isEmpty else { return nil }
        let index = ids.firstIndex(of: selectedID) ?? 0
        let next = forward ? (index + 1) % ids.count : (index == 0 ? ids.count - 1 : index - 1)
        return ids[next]
    }
}

struct CatalogHeroCarousel: View {
    let items: [MediaItem]
    let savedIDs: Set<String>
    let onDetails: (MediaItem) -> Void
    let onPlay: (MediaItem) -> Void
    let onSave: (MediaItem) -> Void
    @State private var selectedID: String
    @AppStorage("cinenex.featuredStyle") private var featuredStyle = "immersive"
    @AppStorage("cinenex.reduceMotion") private var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .body) private var standardHeight: CGFloat = 440

    init(items: [MediaItem], savedIDs: Set<String>, onDetails: @escaping (MediaItem) -> Void,
         onPlay: @escaping (MediaItem) -> Void, onSave: @escaping (MediaItem) -> Void) {
        self.items = items
        self.savedIDs = savedIDs
        self.onDetails = onDetails
        self.onPlay = onPlay
        self.onSave = onSave
        // This is only the initial seed. Later catalog updates reconcile the stable selection.
        _selectedID = State(initialValue: items.first?.id ?? "")
    }

    private var ids: [String] { items.map(\.id) }
    private var page: Int { ids.firstIndex(of: selectedID) ?? 0 }
    private var fullBleed: Bool { featuredStyle == "fullBleed" }
    private var height: CGFloat {
        if verticalSizeClass == .compact { return min(max(standardHeight * 0.76, 280), 660) }
        return min(max(featuredStyle == "compact" ? standardHeight * 0.73 : standardHeight, 300), 900)
    }

    var body: some View {
        VStack(spacing: 6) {
            TabView(selection: $selectedID) {
                ForEach(items) { item in
                    CatalogFeatureCard(item: item, saved: savedIDs.contains(item.id),
                                       onDetails: { onDetails(item) }, onPlay: { onPlay(item) }, onSave: { onSave(item) },
                                       presentationHeight: height, fullBleed: fullBleed)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            .padding(.horizontal, fullBleed ? 0 : 20)
            .accessibilityIdentifier("home.featuredCarousel")
            if items.count > 1 {
                HStack(spacing: 12) {
                    pageButton(forward: false)
                    Spacer(minLength: 4)
                    HStack(spacing: 5) {
                        ForEach(items) { item in
                            Capsule().fill(selectedID == item.id ? Color.cineNexAccent : Color.secondary.opacity(0.35))
                                .frame(width: selectedID == item.id ? 18 : 5, height: 5)
                        }
                    }.accessibilityHidden(true)
                    Text("\(page + 1) / \(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel("Featured title \(page + 1) of \(items.count)")
                    Spacer(minLength: 4)
                    pageButton(forward: true)
                }.padding(.horizontal, 20)
            }
        }
        .onChange(of: ids) { _, newIDs in
            selectedID = HomeHeroPaging.reconciledID(selectedID, in: newIDs)
        }
    }

    private func pageButton(forward: Bool) -> some View {
        Button {
            guard let next = HomeHeroPaging.adjacentID(to: selectedID, in: ids, forward: forward) else { return }
            if reduceMotion || systemReduceMotion { selectedID = next }
            else { withAnimation(.easeInOut(duration: 0.22)) { selectedID = next } }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.subheadline.bold()).frame(width: 44, height: 44).cineNexGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? "Next featured title" : "Previous featured title")
        .accessibilityValue("Featured title \(page + 1) of \(items.count)")
    }
}

/// Malformed metadata must never overflow an integer conversion in a visible progress label.
enum HomeResumeProgress {
    static func label(position: Double, duration: Double) -> String {
        guard position.isFinite, position >= 0 else { return "Ready to resume" }
        if duration.isFinite, duration > 0 {
            let remaining = ceil(max(0, (duration - position) / 60))
            guard remaining.isFinite, remaining <= Double(Int32.max) else { return "Ready to resume" }
            let minutes = Int(remaining)
            return minutes > 0 ? "\(minutes) min remaining" : "Almost finished"
        }
        let elapsed = position / 60
        guard elapsed <= Double(Int32.max) else { return "Ready to resume" }
        return "\(Int(elapsed)) min watched"
    }
}

struct CatalogContinueCard: View {
    let item: MediaItem
    let progress: PlaybackProgress?
    let onDetails: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPlay) {
                ZStack {
                    Color.cineNexSurface
                    CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 38)
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "play.fill").font(.title3.bold()).foregroundStyle(.white)
                        .frame(width: 48, height: 48).cineNexGlass(in: Circle(), interactive: false)
                }
                .frame(height: 142).clipShape(RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    ProgressView(value: progress?.completionFraction ?? 0).tint(Color.cineNexAccent)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }.accessibilityLabel("Resume \(item.title)")
            Button(action: onDetails) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
                    Text(progressLabel).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.accessibilityLabel("Details for \(item.title)")
        }.buttonStyle(.plain)
    }

    private var progressLabel: String {
        guard let progress else { return "Ready to resume" }
        return HomeResumeProgress.label(position: progress.position, duration: progress.duration)
    }

}

struct CatalogLandscapeTile: View {
    let item: MediaItem
    @AppStorage("cinenex.showRatings") private var showRatings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CachedPosterImage(url: item.posterURL, fallbackSymbol: item.symbol, symbolSize: 34)
                .frame(height: 132).background(Color.cineNexSurface).clipShape(RoundedRectangle(cornerRadius: 16))
            Text(item.title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
            HStack(spacing: 8) {
                Text(item.yearLabel ?? item.kind.rawValue)
                if showRatings, let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }.contentShape(Rectangle())
    }
}
