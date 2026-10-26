import SwiftUI

struct PlaybackDiagnosticsView: View {
    @State private var events = PlaybackDiagnostics.events

    var body: some View {
        List {
            Section {
                Text("If the app closes during playback, these startup stages remain available after reopening it. They identify how far startup reached; they are not an iOS crash report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if events.isEmpty {
                    Text("No playback attempts recorded.")
                } else {
                    Text(events.reversed().joined(separator: "\n\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section {
                ShareLink("Share startup diagnostics", item: events.joined(separator: "\n"))
                Button("Refresh") { events = PlaybackDiagnostics.events }
                Button("Clear", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: PlaybackDiagnostics.storageKey)
                    events = []
                }
            }
        }
        .navigationTitle("Playback diagnostics")
    }
}
