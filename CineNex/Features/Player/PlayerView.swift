import AVKit
import SwiftUI

struct PlayerView: View {
    let item: MediaItem
    @ObservedObject var progressStore: PlaybackProgressStore
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var playbackError: String?
    @State private var timeObserver: Any?
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var subtitleGroup: AVMediaSelectionGroup?
    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var subtitleOptions: [AVMediaSelectionOption] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if item.streamURL != nil {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .accessibilityLabel("Video player for \(item.title)")
            } else {
                ContentUnavailableView("No playable source", systemImage: "play.slash", description: Text("This title does not currently have a playable media URL."))
            }
            VStack {
                HStack(spacing: 10) {
                    Button {
                        saveCurrentProgress()
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

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    if audioOptions.count > 1, let audioGroup {
                        Menu {
                            ForEach(Array(audioOptions.enumerated()), id: \.offset) { entry in
                                Button(entry.element.displayName) {
                                    selectAudio(entry.element, in: audioGroup)
                                }
                            }
                        } label: {
                            Image(systemName: "waveform")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .accessibilityLabel("Select audio track")
                    }

                    if !subtitleOptions.isEmpty, let subtitleGroup {
                        Menu {
                            Button("Off") {
                                selectSubtitle(nil, in: subtitleGroup)
                            }
                            ForEach(Array(subtitleOptions.enumerated()), id: \.offset) { entry in
                                Button(entry.element.displayName) {
                                    selectSubtitle(entry.element, in: subtitleGroup)
                                }
                            }
                        } label: {
                            Image(systemName: "captions.bubble")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .accessibilityLabel("Select subtitles")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden()
        .onAppear(perform: startPlayback)
        .onDisappear {
            saveCurrentProgress()
            let position = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? 0
            Task {
                await TraktIntegration.shared.scrobbleStop(
                    for: item,
                    position: position.isFinite ? position : 0,
                    duration: duration.isFinite ? duration : 0
                )
            }
            player.pause()
            if let timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            player.replaceCurrentItem(with: nil)
            audioGroup = nil
            subtitleGroup = nil
            audioOptions = []
            subtitleOptions = []
        }
        .alert("Unable to play media", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("Close", role: .cancel) { playbackError = nil; dismiss() }
        } message: {
            Text(playbackError ?? "The media source could not be loaded.")
        }
    }

    private func startPlayback() {
        guard let url = item.streamURL else { return }
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 600),
            queue: .main
        ) { time in
            let position = time.seconds
            let duration = player.currentItem?.duration.seconds ?? 0
            guard position.isFinite else { return }
            Task { @MainActor in
                progressStore.record(itemID: item.id, position: position, duration: duration.isFinite ? duration : 0)
            }
        }

        Task { @MainActor in
            for _ in 0..<100 {
                guard player.currentItem === playerItem else { return }
                switch playerItem.status {
                case .readyToPlay:
                    await loadTrackOptions(for: playerItem)
                    guard player.currentItem === playerItem else { return }
                    let position = progressStore.progress(for: item.id)?.position ?? 0
                    if position > 5 {
                        await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                    }
                    player.play()
                    Task { await TraktIntegration.shared.scrobbleStart(for: item) }
                    return
                case .failed:
                    playbackError = playerItem.error?.localizedDescription ?? "The source may be unavailable or use an unsupported format."
                    return
                case .unknown:
                    try? await Task.sleep(for: .milliseconds(100))
                @unknown default:
                    playbackError = "The media player reported an unsupported state."
                    return
                }
            }
            if playerItem.status == .unknown {
                playbackError = "The source took too long to become ready. Check your connection and try again."
            }
        }
    }

    @MainActor
    private func loadTrackOptions(for playerItem: AVPlayerItem) async {
        let asset = playerItem.asset
        let loadedAudioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        let loadedSubtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        guard player.currentItem === playerItem else { return }

        audioGroup = loadedAudioGroup
        audioOptions = loadedAudioGroup?.options ?? []
        subtitleGroup = loadedSubtitleGroup
        subtitleOptions = loadedSubtitleGroup?.options ?? []
    }

    private func selectAudio(_ option: AVMediaSelectionOption, in group: AVMediaSelectionGroup) {
        guard let currentItem = player.currentItem else { return }
        currentItem.select(option, in: group)
    }

    private func selectSubtitle(_ option: AVMediaSelectionOption?, in group: AVMediaSelectionGroup) {
        guard let currentItem = player.currentItem else { return }
        currentItem.select(option, in: group)
    }

    private func saveCurrentProgress() {
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard position.isFinite else { return }
        progressStore.record(itemID: item.id, position: position, duration: duration.isFinite ? duration : 0)
    }
}
