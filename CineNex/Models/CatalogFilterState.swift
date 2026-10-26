import Foundation

/// Filters only metadata the catalog actually supplies. Unknown years/ratings do not pass
/// an explicit bound; no age classification or source availability is inferred.
struct CatalogFilterState: Equatable {
    var query = ""
    var kind = "all"
    var genre = ""
    var earliestYear = 0
    var latestYear = 0
    var minimumRating = 0
    var hideUnrated = false
    var requirePoster = false

    var activeCount: Int {
        [!query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kind != "all", !genre.isEmpty,
         earliestYear > 0, latestYear > 0, minimumRating > 0, hideUnrated, requirePoster].filter { $0 }.count
    }

    func matches(_ item: MediaItem) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty || item.title.localizedCaseInsensitiveContains(text) else { return false }
        guard kind == "all" || (kind == "movies" && item.kind == .movie) || (kind == "series" && item.kind == .series) else { return false }
        if !genre.isEmpty {
            let genres = item.genre.components(separatedBy: CharacterSet(charactersIn: ",·/"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard genres.contains(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) else { return false }
        }
        guard earliestYear == 0 || item.year >= earliestYear else { return false }
        guard latestYear == 0 || (item.year > 0 && item.year <= latestYear) else { return false }
        guard minimumRating == 0 || (item.rating ?? -1) >= Double(minimumRating) else { return false }
        guard !hideUnrated || (item.rating ?? 0) > 0 else { return false }
        guard !requirePoster || item.posterURL != nil else { return false }
        return true
    }
}
