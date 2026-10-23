import SwiftUI

struct TraktHistoryReviewView: View {
    let movies: [TraktHistoryMovie]
    @ObservedObject var store: TraktHistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>
    @State private var resultMessage: String?
    @State private var didImport = false

    init(movies: [TraktHistoryMovie], store: TraktHistoryStore) {
        self.movies = movies
        self.store = store
        _selectedIDs = State(initialValue: Set(movies.map(\.id)))
    }

    private var selectedMovies: [TraktHistoryMovie] {
        movies.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review watched movies")
                            .font(.headline)
                        Text("Select the history records to keep in CineNex. This import does not modify Trakt or your Continue Watching progress.")
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

                Section("Watched movies from Trakt") {
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
                                    Text([movie.year.map(String.init), movie.watchedAt.map { String($0.prefix(10)) }, movie.playCount > 1 ? "\(movie.playCount) plays" : nil].compactMap { $0 }.joined(separator: " · "))
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
            .navigationTitle("Import Trakt History")
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
                            let count = selectedMovies.count
                            let added = store.importMovies(selectedMovies)
                            resultMessage = "Imported \(count) selected records; added \(added) new movies. Existing records were merged without duplicates."
                            didImport = true
                        }
                    }
                    .disabled(!didImport && selectedIDs.isEmpty)
                }
            }
        }
    }
}
