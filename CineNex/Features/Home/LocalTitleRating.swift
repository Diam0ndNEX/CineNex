import SwiftUI

/// Explicit local feedback, never advertised as a Trakt/account write.
struct LocalTitleRating: View {
    let itemID: String
    @AppStorage("cinenex.localTitleRatings.v1") private var stored = "{}"
    private var ratings: [String: Int] {
        guard let data = stored.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }
    private var rating: Int { min(5, max(0, ratings[itemID] ?? 0)) }
    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { value in
                Button { save(value == rating ? 0 : value) } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title2).foregroundStyle(value <= rating ? Color.yellow : Color.secondary)
                        .frame(minWidth: 36, minHeight: 44)
                }
                .accessibilityLabel("Rate \(value) out of 5")
                .accessibilityValue(value <= rating ? "Selected" : "Not selected")
                .accessibilityHint("Saved only on this device")
            }
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
            .contextMenu { Button("Clear local rating") { save(0) } }
    }
    private func save(_ value: Int) {
        var next = ratings
        next[itemID] = value == 0 ? nil : value
        if let data = try? JSONEncoder().encode(next) { stored = String(decoding: data, as: UTF8.self) }
    }
}
