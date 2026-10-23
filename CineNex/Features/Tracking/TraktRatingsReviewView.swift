import SwiftUI

struct TraktRatingsReviewView: View {
    let movies: [TraktRatingMovie]
    @ObservedObject var store: TraktRatingStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>
    @State private var resultMessage: String?
    @State private var didImport = false

    init(movies: [TraktRatingMovie], store: TraktRatingStore) {
        self.movies = movies
        self.store = store
        _selectedIDs = State(initialValue: Set(movies.map(\.id)))
    }

    private var selectedMovies: [TraktRatingMovie] {
        movies.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review movie ratings")
                            .font(.headline)
                        Text("Choose which ratings to save locally in CineNex. Importing never changes your Trakt ratings.")
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

                Section("Ratings from Trakt") {
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
                                    Text([movie.year.map(String.init), "\(movie.rating)/10 ★", movie.ratedAt.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(movie.title), rated \(movie.rating) out of 10, \(selectedIDs.contains(movie.id) ? "selected" : "not selected")")
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
            .navigationTitle("Import Trakt Ratings")
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
                            resultMessage = "Imported \(selectedCount) selected ratings; added \(added) new movies. Existing ratings were merged without duplicates."
                            didImport = true
                        }
                    }
                    .disabled(!didImport && selectedIDs.isEmpty)
                }
            }
        }
    }
}
