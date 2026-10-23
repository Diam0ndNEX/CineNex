import SwiftUI

struct TraktWatchlistReviewView: View {
    let movies: [TraktWatchlistMovie]
    @ObservedObject var store: TraktWatchlistStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>
    @State private var resultMessage: String?
    @State private var didImport = false

    init(movies: [TraktWatchlistMovie], store: TraktWatchlistStore) {
        self.movies = movies
        self.store = store
        _selectedIDs = State(initialValue: Set(movies.map(\.id)))
    }

    private var selectedMovies: [TraktWatchlistMovie] {
        movies.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review before importing")
                            .font(.headline)
                        Text("Choose which Trakt movies to save to CineNex’s local watchlist. This does not change your Trakt account or your favorites.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(selectedIDs.count) of \(movies.count) selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cineNexAccent)
                    }
                    .padding(.vertical, 4)

                    Button(selectedIDs.count == movies.count ? "Deselect all" : "Select all") {
                        if selectedIDs.count == movies.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(movies.map(\.id))
                        }
                    }
                }

                Section("Movies from Trakt") {
                    ForEach(movies) { movie in
                        Button {
                            if selectedIDs.contains(movie.id) {
                                selectedIDs.remove(movie.id)
                            } else {
                                selectedIDs.insert(movie.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(movie.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(movie.id) ? Color.cineNexAccent : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(movie.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text([movie.year.map(String.init), movie.tmdbID.map { "TMDB \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(movie.title), \(selectedIDs.contains(movie.id) ? "selected" : "not selected")")
                    }
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import Trakt Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didImport ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(didImport ? "Done" : "Import \(selectedIDs.count)") {
                        if didImport {
                            dismiss()
                        } else {
                            let selectedCount = selectedMovies.count
                            let added = store.importMovies(selectedMovies)
                            resultMessage = "Imported \(selectedCount) selected movies; added \(added) new entries. Existing entries were updated without creating duplicates."
                            didImport = true
                        }
                    }
                    .disabled(!didImport && selectedIDs.isEmpty)
                }
            }
        }
    }
}

