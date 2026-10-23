import Foundation

protocol CatalogProvider {
    var providerName: String { get }
    func fetchCatalog() async throws -> [MediaItem]
}

struct DemoCatalogProvider: CatalogProvider {
    let providerName = "CineNex Demo Catalog"

    func fetchCatalog() async throws -> [MediaItem] {
        MediaItem.demoCatalog
    }
}
