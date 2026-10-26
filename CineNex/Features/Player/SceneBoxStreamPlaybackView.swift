import AVKit
import SwiftUI
import SwiftVLC
import UIKit

@MainActor
struct SceneBoxStreamPlaybackView: View {
    let source: PlaybackSource
    let item: MediaItem
    let seasonNumber: Int
    let episodeNumber: Int
    let onClose: () -> Void

    @AppStorage("cinenex.preferredSubtitleLanguage") private var preferredSubtitleLanguage = SubtitleLanguage.deviceDefault.code
    @State private var chrome = SceneBoxChromeVisibility()
    @State private var isStalled = false
    @State private var didSeekToStart = false
    @State private var resumePosition = 0.0
    @State private var previousIdleTimerDisabled = false
    @State private var player = SwiftVLC.Player()
    @State private var subtitles = SubtitlesController()
    @State private var nowPlayingController: SceneBoxNowPlayingController?
    @State private var isSettingsPresented = false
    @State private var positionSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var failure: String?
    @State private var playbackTask: Task<Void, Never>?
    @State private var monitorTask: Task<Void, Never>?
    @State private var progressTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoView(player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            Button {
                guard failure == nil else { return }
                chrome.screenTapped(shouldAutoHide: player.isPlaying && !isBuffering)
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()
            .accessibilityLabel(chrome.isVisible ? "Hide playback controls" : "Show playback controls")

            LinearGradient(
                colors: [.black.opacity(0.78), .clear, .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .opacity(chrome.isVisible ? 1 : 0)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close player")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(source.providerName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Playback settings")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .opacity(chrome.isVisible || failure != nil ? 1 : 0)
                .allowsHitTesting(chrome.isVisible || failure != nil)

                Spacer()

                if let failure {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.yellow)
                        Text("Playback failed")
                            .font(.title3.bold())
                        Text(failure)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.78))
                        HStack(spacing: 12) {
                            Button("Retry") {
                                self.failure = nil
                                startPlayback()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Close", role: .cancel, action: onClose)
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 360)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SceneBoxTransportControls(
                        player: player,
                        positionSeconds: $positionSeconds,
                        durationSeconds: $durationSeconds,
                        onEditingChanged: { editing in
                            if editing {
                                chrome.holdVisible()
                            } else {
                                chrome.releaseHold(autoHide: player.isPlaying && !isBuffering)
                            }
                        },
                        onInteraction: { chrome.interacted(autoHide: player.isPlaying && !isBuffering) }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
                    .opacity(chrome.isVisible ? 1 : 0)
                    .allowsHitTesting(chrome.isVisible)
                }
            }
            if isBuffering {
                ProgressView("Buffering…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .sheet(isPresented: $isSettingsPresented) {
            SceneBoxPlaybackSettingsPanel(player: player, subs: subtitles) {
                isSettingsPresented = false
            }
            .presentationBackground(.clear)
        }
        .onChange(of: player.subtitleTracks.count) { _, _ in
            subtitles.syncEmbedded(on: player)
        }
        .onChange(of: player.selectedSubtitleTrack?.id) { _, _ in
            subtitles.syncEmbedded(on: player)
        }
        .task(id: chrome.autoHideID) { await chrome.autoHide() }
        .onChange(of: isSettingsPresented) { _, open in
            if open {
                chrome.holdVisible()
            } else {
                chrome.releaseHold(autoHide: player.isPlaying && !isBuffering)
            }
        }
        .onChange(of: player.isPlaying) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = playing || previousIdleTimerDisabled
            guard failure == nil, !isBuffering else { return }
            if playing { chrome.playbackStarted() }
            else { chrome.reveal(autoHide: false) }
        }
        .onChange(of: isBuffering) { _, buffering in
            if buffering { chrome.reveal(autoHide: false) }
            else if player.isPlaying { chrome.playbackStarted() }
        }
        .onChange(of: player.isSeekable) { _, _ in restoreProgressIfReady() }
        .onChange(of: player.duration) { _, _ in restoreProgressIfReady() }
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            startPlayback()
        }
        .onDisappear {
            playbackTask?.cancel()
            monitorTask?.cancel()
            progressTask?.cancel()
            saveProgress()
            chrome.viewDisappeared()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            player.stop()
            nowPlayingController?.end()
            nowPlayingController = nil
            PlaybackAudioSession.deactivate()
            let position = positionSeconds
            let duration = durationSeconds
            Task {
                await TraktIntegration.shared.scrobbleStop(
                    for: item,
                    position: position.isFinite ? position : 0,
                    duration: duration.isFinite ? duration : 0
                )
            }
        }
    }

    private func startPlayback() {
        playbackTask?.cancel()
        monitorTask?.cancel()
        progressTask?.cancel()
        saveProgress()
        nowPlayingController?.end()
        nowPlayingController = nil
        player.stop()
        positionSeconds = 0
        durationSeconds = 0
        isStalled = false
        didSeekToStart = false
        resumePosition = item.kind == .movie
            ? PlaybackProgressStore.shared.progress(for: item.id)?.position ?? 0 : 0
        subtitles = SubtitlesController()
        chrome.reveal(autoHide: false)
        failure = nil

        playbackTask = Task { @MainActor in
            do {
                try await PlaybackAudioSession.activate()
                try Task.checkCancellation()
                let media = try Media(url: source.url)
                if !source.url.isFileURL {
                    let isTorrent = source.url.host == "127.0.0.1" || source.url.host == "localhost"
                    media.addOption(":network-caching=\(isTorrent ? 8000 : 1500)")
                    if !isTorrent { media.addOption(":http-reconnect") }
                }
                try player.play(media)
                loadSubtitlesIfAvailable()
                let controller = SceneBoxNowPlayingController(player: player, title: item.title)
                controller.begin(artworkURL: item.posterURL)
                nowPlayingController = controller
                monitorPlayback()
                trackProgress()
                Task { await TraktIntegration.shared.scrobbleStart(for: item) }
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
                PlaybackAudioSession.deactivate()
            }
        }
    }

    private func monitorPlayback() {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor in
            for await state in player.stateTransitions {
                guard !Task.isCancelled else { return }
                if state == .error {
                    failure = "The source could not be decoded or stopped responding. Retry or select another source."
                    chrome.reveal(autoHide: false)
                    player.pause()
                    return
                }
            }
        }
    }

    private func trackProgress() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            var lastSeen = player.currentTime
            var frozenTicks = 0
            var lastSave = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                positionSeconds = seconds(player.currentTime)
                durationSeconds = player.duration.map(seconds) ?? 0
                if player.isPlaying, player.currentTime == lastSeen {
                    frozenTicks += 1
                } else {
                    frozenTicks = 0
                }
                lastSeen = player.currentTime
                isStalled = frozenTicks >= 3
                if Date().timeIntervalSince(lastSave) >= 5 {
                    saveProgress()
                    lastSave = Date()
                }
                nowPlayingController?.refresh()
            }
        }
    }

    private var isBuffering: Bool {
        guard failure == nil else { return false }
        switch player.state {
        case .opening, .buffering: return true
        case .playing: return player.currentTime == .zero || isStalled
        default: return false
        }
    }

    private func restoreProgressIfReady() {
        guard !didSeekToStart, player.isSeekable,
              let duration = player.duration, duration > .zero else { return }
        didSeekToStart = true
        guard resumePosition.isFinite, resumePosition > 5,
              resumePosition < seconds(duration) - 30 else { return }
        try? player.seek(to: .seconds(resumePosition))
    }

    private func saveProgress() {
        guard item.kind == .movie, failure == nil, player.currentTime > .zero else { return }
        PlaybackProgressStore.shared.record(
            itemID: item.id,
            position: seconds(player.currentTime),
            duration: player.duration.map(seconds) ?? durationSeconds,
            item: item
        )
    }

    private func loadSubtitlesIfAvailable() {
        guard let imdbID = item.externalIMDbID?.trimmingCharacters(in: .whitespacesAndNewlines),
              imdbID.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil else {
            return
        }
        subtitles.load(
            context: SubtitleContext(
                imdbID: imdbID,
                type: item.kind == .movie ? .movie : .series,
                season: item.kind == .series ? seasonNumber : nil,
                episode: item.kind == .series ? episodeNumber : nil
            ),
            preferred: preferredSubtitleLanguage,
            player: player
        )
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private struct SceneBoxTransportControls: View {
    let player: SwiftVLC.Player
    @Binding var positionSeconds: Double
    @Binding var durationSeconds: Double
    let onEditingChanged: (Bool) -> Void
    let onInteraction: () -> Void
    @State private var scrubPosition: Double?

    private var sliderPosition: Double {
        min(max(scrubPosition ?? positionSeconds, 0), max(durationSeconds, 1))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 42) {
                Button {
                    try? player.seek(by: .seconds(-10), fast: true)
                    onInteraction()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 27, weight: .medium))
                        .frame(width: 48, height: 48)
                }
                .disabled(!player.isSeekable)
                .accessibilityLabel("Back 10 seconds")

                Button {
                    player.togglePlayPause()
                    onInteraction()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 62, height: 62)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")

                Button {
                    try? player.seek(by: .seconds(10), fast: true)
                    onInteraction()
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
                        onEditingChanged(editing)
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
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
