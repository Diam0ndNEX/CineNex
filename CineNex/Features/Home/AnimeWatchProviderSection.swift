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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watch anime")
                    .font(.title3.bold())
                Spacer()
                Text("WEB SOURCES")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }

            Text("Choose a site, then select the matching season, episode, and available server on that site.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AnimeWebsiteProvider.supported) { provider in
                        Button {
                            onSelect(provider)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.subheadline)
                                Text(provider.name)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.cineNexSurface, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color.cineNexAccent.opacity(0.65), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the anime search on \\(provider.name)")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
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
