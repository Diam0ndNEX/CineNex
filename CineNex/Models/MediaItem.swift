import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case movie = "Movie"
    case series = "Series"

    var id: String { rawValue }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: MediaKind
    let year: Int
    let genre: String
    let synopsis: String
    let symbol: String
    let runtime: String
    let streamURL: URL?
    var posterURL: URL? = nil
    var rating: Double? = nil
    var externalID: Int? = nil
    var metadataProvider: String = "demo"

    static let demoCatalog: [MediaItem] = [
        MediaItem(
            id: "big-buck-bunny",
            title: "Big Buck Bunny",
            kind: .movie,
            year: 2008,
            genre: "Animation",
            synopsis: "A gentle giant rabbit enjoys a peaceful day until three mischievous rodents disrupt his garden. This open short film is included as a playable sample for testing CineNex.",
            symbol: "hare.fill",
            runtime: "10 min",
            streamURL: URL(string: "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
        ),
        MediaItem(
            id: "planet-earth",
            title: "Planet Earth",
            kind: .series,
            year: 2006,
            genre: "Documentary",
            synopsis: "Explore extraordinary landscapes and wildlife in this sample series entry. A real provider can later supply verified episode metadata and playback sources.",
            symbol: "globe.americas.fill",
            runtime: "Episodes",
            streamURL: nil
        ),
        MediaItem(
            id: "the-last-frontier",
            title: "The Last Frontier",
            kind: .movie,
            year: 2024,
            genre: "Adventure",
            synopsis: "A fictional catalog entry used to exercise the details and discovery interface before a live catalog provider is connected.",
            symbol: "mountain.2.fill",
            runtime: "2 hr 4 min",
            streamURL: nil
        ),
        MediaItem(
            id: "midnight-signal",
            title: "Midnight Signal",
            kind: .series,
            year: 2025,
            genre: "Mystery",
            synopsis: "A fictional series entry for testing search, favorites, and detail navigation. No real episode stream is attached.",
            symbol: "antenna.radiowaves.left.and.right",
            runtime: "Episodes",
            streamURL: nil
        ),
        MediaItem(
            id: "ocean-below",
            title: "Ocean Below",
            kind: .movie,
            year: 2023,
            genre: "Documentary",
            synopsis: "A sample documentary listing that demonstrates how CineNex presents catalog information even when a provider has not supplied a playable source.",
            symbol: "water.waves",
            runtime: "1 hr 32 min",
            streamURL: nil
        ),
        MediaItem(
            id: "city-of-stars",
            title: "City of Stars",
            kind: .movie,
            year: 2022,
            genre: "Drama",
            synopsis: "A fictional drama entry used to make the first home screen feel populated while the provider system is being built.",
            symbol: "building.2.fill",
            runtime: "1 hr 48 min",
            streamURL: nil
        )
    ]
}
