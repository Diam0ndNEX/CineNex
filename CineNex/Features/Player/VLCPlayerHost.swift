import SwiftUI
import SwiftVLC

@MainActor
enum VLCPlaybackRuntime {
    static func makePlayer() async throws -> SwiftVLC.Player {
        PlaybackDiagnostics.record("Initializing VLC instance")
        let instance = try await Task.detached(priority: .userInitiated) {
            try VLCInstance(arguments: VLCInstance.defaultArguments, applicationName: "CineNex")
        }.value
        try Task.checkCancellation()
        PlaybackDiagnostics.record("Creating VLC player")
        return SwiftVLC.Player(instance: instance)
    }
}

/// Owns initialization so a missing or unusable VLC instance becomes a visible error.
@MainActor
struct VLCPlayerHost<Content: View>: View {
    @State private var player: SwiftVLC.Player?
    @State private var failure: String?
    @State private var attempt = 0
    let onClose: () -> Void
    @ViewBuilder let content: (SwiftVLC.Player) -> Content

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                content(player)
            } else if let failure {
                VStack(spacing: 18) {
                    Label("Player unavailable", systemImage: "exclamationmark.triangle")
                        .font(.title2.bold())
                    Text(failure).multilineTextAlignment(.center)
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(.borderedProminent)
                    Button("Back to sources", action: onClose)
                }
                .padding(24)
            } else {
                VStack(spacing: 20) {
                    ProgressView("Preparing video player…")
                    Button("Cancel", action: onClose)
                }
            }
        }
        .foregroundStyle(.white)
        .task(id: attempt) {
            failure = nil
            do {
                player = try await VLCPlaybackRuntime.makePlayer()
                PlaybackDiagnostics.record("VLC player ready")
            } catch is CancellationError {
                return
            } catch {
                PlaybackDiagnostics.record("VLC initialization failed: \(error.localizedDescription)")
                failure = error.localizedDescription
            }
        }
    }
}
