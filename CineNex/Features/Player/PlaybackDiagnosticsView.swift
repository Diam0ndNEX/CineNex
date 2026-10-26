import SwiftUI

struct PlaybackDiagnosticsView: View {
    @State private var report = PlaybackDiagnostics.report

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Startup and provider report")
                    .font(.title2.bold())
                Text("Includes native settings conversion, session construction, memory usage and provider response counts. Reopen this screen after an unexpected exit. A process crash or system termination may leave only the last completed checkpoint; this report does not replace an iOS crash report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    ShareLink("Share report", item: report)
                    Spacer()
                    Button("Refresh") { report = PlaybackDiagnostics.report }
                }
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Clear report", role: .destructive) {
                    PlaybackDiagnostics.clear()
                    report = PlaybackDiagnostics.report
                }
            }
            .padding(20)
        }
        .navigationTitle("Playback diagnostics")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                report = PlaybackDiagnostics.report
            }
        }
    }
}
