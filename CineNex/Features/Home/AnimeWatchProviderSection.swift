import SwiftUI

struct AnimeWebsiteProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let searchBaseURL: URL
    let queryParameter: String

    func searchURL(for anime: AnimeTitle) -> URL? {
        guard var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: queryParameter, value: anime.title)
        ]
        guard let url = components.url,
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

    static let supported: [AnimeWebsiteProvider] = [
        AnimeWebsiteProvider(
            id: "miruro",
            name: "Miruro",
            searchBaseURL: URL(string: "https://www.miruro.tv/search")!,
            queryParameter: "query"
        ),
        AnimeWebsiteProvider(
            id: "anikoto",
            name: "Anikoto",
            searchBaseURL: URL(string: "https://anikototv.to/search")!,
            queryParameter: "keyword"
        ),
        AnimeWebsiteProvider(
            id: "crunchyroll",
            name: "Crunchyroll",
            searchBaseURL: URL(string: "https://www.crunchyroll.com/search")!,
            queryParameter: "q"
        )
    ]
}

struct AnimeWatchProviderSection: View {
    let anime: AnimeTitle
    let onSelect: (AnimeWebsiteProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Watch options", systemImage: "play.rectangle.fill")
                .font(.caption.weight(.bold)).foregroundStyle(Color.cineNexAccent)
            Text("Choose a website").font(.title3.bold())
            Text("Search this anime on a website, then choose the matching season, episode and server there.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(AnimeWebsiteProvider.supported) { provider in
                Button { onSelect(provider) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill").font(.subheadline)
                            .frame(width: 42, height: 42)
                            .background(Color.cineNexAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.name).font(.headline).foregroundStyle(.primary)
                            Text("Open title search").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.bold())
                    }.foregroundStyle(Color.cineNexAccent)
                        .padding(12).background(Color.cineNexBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                    .accessibilityHint("Opens the anime search on \(provider.name)")
            }
            Label("Website playback and account requirements vary by provider.", systemImage: "info.circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AnimeWebsitePlaybackSheet: View {
    let anime: AnimeTitle
    let provider: AnimeWebsiteProvider

    @Environment(\.dismiss) private var dismiss
    @State private var navigationFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let url = provider.searchURL(for: anime) {
                    EmbedWebView(url: url, cleanerEnabled: false) {
                        navigationFailed = true
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Search unavailable",
                        systemImage: "link.slash",
                        description: Text("A valid secure search URL could not be created.")
                    )
                }
            }
            .background(.black)
            .navigationTitle(provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(anime.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
            }
            .alert("Website could not load", isPresented: $navigationFailed) {
                Button("OK", role: .cancel) { navigationFailed = false }
            } message: {
                Text("This website may be unavailable or may have changed its address. Try another source from the anime details.")
            }
        }
        .tint(Color.cineNexAccent)
        .preferredColorScheme(.dark)
    }
}
