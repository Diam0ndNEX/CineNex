import AVKit
import SwiftUI

struct PlayerView: View {
    let item: MediaItem

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var playbackError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item.streamURL != nil {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .accessibilityLabel("Video player for \(item.title)")
            } else {
                ContentUnavailableView(
                    "No playable source",
                    systemImage: "play.slash",
                    description: Text("This title does not currently have a playable media URL.")
                )
            }

            VStack {
                HStack {
                    Button {
                        player.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Close player")
                    Spacer()
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden()
        .onAppear(perform: startPlayback)
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .alert("Unable to play media", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("Close", role: .cancel) {
                playbackError = nil
                dismiss()
            }
        } message: {
            Text(playbackError ?? "The media source could not be loaded.")
        }
    }

    private func startPlayback() {
        guard let url = item.streamURL else { return }
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        player.play()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if player.currentItem?.status == .failed {
                playbackError = player.currentItem?.error?.localizedDescription
                    ?? "The source may be unavailable or use an unsupported format."
            }
        }
    }
}
