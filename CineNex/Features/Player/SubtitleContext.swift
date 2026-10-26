import Foundation

struct SubtitleContext: Sendable, Equatable {
    let imdbID: String
    let type: String
    let season: Int?
    let episode: Int?
}
