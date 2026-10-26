import AVKit
import SwiftUI
import SwiftVLC

@MainActor
struct PlayerView: View {
    let item: MediaItem
    @ObservedObject var progressStore: PlaybackProgressStore
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var vlcPlayer = SwiftVLC.Player()
    @State private var isUsingVLC = true
    @State private var playbackError: String?
    @State private var timeObserver: Any?
    @State private var progressTask: Task<Void, Never>?
    @State private var vlcStateTask: Task<Void, Never>?
    @State private var vlcPositionSeconds: Double = 0
    @State private var vlcDurationSeconds: Double = 0
    @State private var subtitlesController = SubtitlesController()
    @AppStorage("cinenex.preferredSubtitleLanguage") private var preferredSubtitleLanguage = SubtitleLanguage.deviceDefault.code
    @State private var isVLCSettingsPresented = false
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var subtitleGroup: AVMediaSelectionGroup?
    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var subtitleOptions: [AVMediaSelectionOption] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if item.streamURL != nil {
                Group {
                    if isUsingVLC {
                        VideoView(vlcPlayer)
                            .accessibilityLabel("VLC video player for \(item.title)")
                    } else {
                        NativePlaybackView(player: player)
                            .accessibilityLabel("Native video player for \(item.title)")
                    }
                }
                .ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    "No playable source",
                    systemImage: "play.slash",
                    description: Text("This title does not currently have a playable media URL.")
                )
            }

            VStack {
                HStack(spacing: 10) {
                    Button {
                        saveCurrentProgress()
                        player.pause()
                        vlcPlayer.pause()
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

                    Menu {
                        Button {
                            switchToVLC()
                        } label: {
                            Label("VLC player", systemImage: isUsingVLC ? "checkmark.circle.fill" : "play.rectangle")
                        }
                        Button {
                            switchToNative()
                        } label: {
                            Label("Apple native player", systemImage: !isUsingVLC ? "checkmark.circle.fill" : "play.rectangle")
                        }
                    } label: {
                        Image(systemName: "switch.2")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Choose playback engine")

                    if isUsingVLC {
                        Button {
                            isVLCSettingsPresented = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .accessibilityLabel("VLC playback settings")
                    }

                    if !isUsingVLC, audioOptions.count > 1, let audioGroup {
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

                    if !isUsingVLC, !subtitleOptions.isEmpty, let subtitleGroup {
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
        .overlay(alignment: .bottom) {
            if isUsingVLC {
                VLCTransportControls(
                    player: vlcPlayer,
                    positionSeconds: $vlcPositionSeconds,
                    durationSeconds: $vlcDurationSeconds
                )
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $isVLCSettingsPresented) {
            SceneBoxPlaybackSettingsPanel(player: vlcPlayer, subs: subtitlesController) {
                isVLCSettingsPresented = false
            }
            .presentationBackground(.clear)
        }
        .onChange(of: vlcPlayer.subtitleTracks.count) { _, _ in
            subtitlesController.syncEmbedded(on: vlcPlayer)
        }
        .onChange(of: vlcPlayer.selectedSubtitleTrack?.id) { _, _ in
            subtitlesController.syncEmbedded(on: vlcPlayer)
        }
        .onAppear(perform: startPlayback)
        .onDisappear {
            saveCurrentProgress()
            let position = currentPositionSeconds
            let duration = currentDurationSeconds
            Task {
                await TraktIntegration.shared.scrobbleStop(
                    for: item,
                    position: position.isFinite ? position : 0,
                    duration: duration.isFinite ? duration : 0
                )
            }
            progressTask?.cancel()
            progressTask = nil
            vlcStateTask?.cancel()
            vlcStateTask = nil
            player.pause()
            vlcPlayer.stop()
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
            Button("Retry") {
                retryPlayback()
            }
            Button("Close", role: .cancel) {
                playbackError = nil
                dismiss()
            }
        } message: {
            Text(playbackError ?? "The media source could not be loaded.")
        }
    }

    private var currentPositionSeconds: Double {
        isUsingVLC ? seconds(vlcPlayer.currentTime) : player.currentTime().seconds
    }

    private var currentDurationSeconds: Double {
        if isUsingVLC {
            return vlcPlayer.duration.map(seconds) ?? 0
        }
        return player.currentItem?.duration.seconds ?? 0
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func startPlayback() {
        guard let url = item.streamURL else { return }
        playbackError = nil
        progressTask?.cancel()
        progressTask = nil
        vlcStateTask?.cancel()
        vlcStateTask = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        vlcPlayer.stop()
        audioGroup = nil
        subtitleGroup = nil
        audioOptions = []
        subtitleOptions = []

        do {
            try vlcPlayer.play(url: url)
            loadSubtitlesIfAvailable()
            isUsingVLC = true
            vlcPositionSeconds = seconds(vlcPlayer.currentTime)
            vlcDurationSeconds = vlcPlayer.duration.map(seconds) ?? 0
            startVLCProgressTracking()
            monitorVLCPlayback(for: url)
            Task { @MainActor in
                for _ in 0..<40 {
                    guard isUsingVLC, !Task.isCancelled else { return }
                    if vlcPlayer.duration != nil {
                        let position = progressStore.progress(for: item.id)?.position ?? 0
                        if position > 5 {
                            try? vlcPlayer.seek(to: .milliseconds(Int64(position * 1_000)))
                        }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            Task { await TraktIntegration.shared.scrobbleStart(for: item) }
        } catch {
            isUsingVLC = false
            startNativePlayback(url: url)
        }
    }

    private func monitorVLCPlayback(for url: URL) {
        vlcStateTask?.cancel()
        vlcStateTask = Task { @MainActor in
            for await state in vlcPlayer.stateTransitions {
                guard !Task.isCancelled, isUsingVLC else { return }
                guard state == .error else { continue }
                saveCurrentProgress()
                vlcStateTask = nil
                vlcPlayer.stop()
                startNativePlayback(url: url)
                return
            }
        }
    }

    private func startVLCProgressTracking() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            var lastProgressSave = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, isUsingVLC else { return }
                vlcPositionSeconds = seconds(vlcPlayer.currentTime)
                vlcDurationSeconds = vlcPlayer.duration.map(seconds) ?? 0
                if Date().timeIntervalSince(lastProgressSave) >= 10 {
                    saveCurrentProgress()
                    lastProgressSave = Date()
                }
            }
        }
    }

    private func startNativePlayback(url: URL) {
        isUsingVLC = false
        progressTask?.cancel()
        progressTask = nil
        vlcStateTask?.cancel()
        vlcStateTask = nil
        vlcPositionSeconds = 0
        vlcDurationSeconds = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        audioGroup = nil
        subtitleGroup = nil
        audioOptions = []
        subtitleOptions = []

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
                progressStore.record(
                    itemID: item.id,
                    position: position,
                    duration: duration.isFinite ? duration : 0,
                    item: item
                )
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
                    playbackError = playerItem.error?.localizedDescription
                        ?? "The source may be unavailable or use an unsupported format."
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

    private func switchToVLC() {
        guard let url = item.streamURL else { return }
        saveCurrentProgress()
        vlcStateTask?.cancel()
        vlcStateTask = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        do {
            try vlcPlayer.play(url: url)
            loadSubtitlesIfAvailable()
            isUsingVLC = true
            startVLCProgressTracking()
            monitorVLCPlayback(for: url)
            let position = progressStore.progress(for: item.id)?.position ?? 0
            if position > 5 {
                Task { @MainActor in
                    for _ in 0..<40 {
                        if vlcPlayer.duration != nil {
                            try? vlcPlayer.seek(to: .milliseconds(Int64(position * 1_000)))
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            }
        } catch {
            isUsingVLC = false
            startNativePlayback(url: url)
        }
    }

    private func switchToNative() {
        guard let url = item.streamURL else { return }
        saveCurrentProgress()
        vlcPlayer.stop()
        startNativePlayback(url: url)
    }

    private func retryPlayback() {
        playbackError = nil
        startPlayback()
    }

    private func loadSubtitlesIfAvailable() {
        guard let imdbID = item.externalIMDbID?.trimmingCharacters(in: .whitespacesAndNewlines),
              imdbID.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil else {
            return
        }
        subtitlesController.load(
            context: SubtitleContext(
                imdbID: imdbID,
                type: item.kind == .movie ? .movie : .series,
                season: nil,
                episode: nil
            ),
            preferred: preferredSubtitleLanguage,
            player: vlcPlayer
        )
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
        let position = currentPositionSeconds
        let duration = currentDurationSeconds
        guard position.isFinite else { return }
        progressStore.record(
            itemID: item.id,
            position: position,
            duration: duration.isFinite ? duration : 0,
            item: item
        )
    }
}


private struct VLCTransportControls: View {
    let player: SwiftVLC.Player
    @Binding var positionSeconds: Double
    @Binding var durationSeconds: Double
    @State private var scrubPosition: Double?

    private var sliderPosition: Double {
        min(max(scrubPosition ?? positionSeconds, 0), max(durationSeconds, 1))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 42) {
                Button {
                    try? player.seek(by: .seconds(-10), fast: true)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 27, weight: .medium))
                        .frame(width: 48, height: 48)
                }
                .disabled(!player.isSeekable)
                .accessibilityLabel("Back 10 seconds")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 62, height: 62)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")

                Button {
                    try? player.seek(by: .seconds(10), fast: true)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 27, weight: .medium))
                        .frame(width: 48, height: 48)
                }
                .disabled(!player.isSeekable)
                .accessibilityLabel("Forward 10 seconds")
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(timecode(scrubPosition ?? positionSeconds))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 42, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { sliderPosition },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(durationSeconds, 1),
                    onEditingChanged: { editing in
                        guard !editing, let target = scrubPosition else { return }
                        try? player.seek(to: .seconds(target))
                        positionSeconds = target
                        scrubPosition = nil
                    }
                )
                .tint(.white)
                .disabled(!player.isSeekable || durationSeconds <= 0)
                .accessibilityLabel("Playback position")

                Text(timecode(durationSeconds))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 42, alignment: .trailing)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}
