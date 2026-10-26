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

    var body: some View {
        VLCPlayerHost(onClose: onClose) { player in
            LoadedSceneBoxStreamPlaybackView(
                source: source, item: item, seasonNumber: seasonNumber,
                episodeNumber: episodeNumber, onClose: onClose, player: player
            )
        }
    }
}

@MainActor
private struct LoadedSceneBoxStreamPlaybackView: View {
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
    let player: SwiftVLC.Player
    @State private var subtitles = SubtitlesController()
    @State private var nowPlayingController: SceneBoxNowPlayingController?
    @State private var isSettingsPresented = false
    @State private var positionSeconds = 0.0
    @State private var durationSeconds = 0.0
    @AppStorage("cinenex.resumePlayback") private var resumePlayback = true
    @AppStorage("cinenex.defaultPlaybackSpeed") private var defaultPlaybackSpeed = 1.0
    @AppStorage("cinenex.bufferStrategy") private var bufferStrategy = "balanced"
    @AppStorage("cinenex.playerControlsDelay") private var controlsDelay = 5
    @AppStorage("cinenex.showTransferHUD") private var showTransferHUD = false
    @State private var sleepDeadline: Date?
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

            VStack(spacing: 0) {
                CineNexGlassGroup(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .cineNexGlass(in: Circle())
                    }
                    .accessibilityLabel("Close player")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline.weight(.semibold))
                            .shadow(color: .black, radius: 3, y: 1)
                            .lineLimit(1)
                        Text(item.kind == .series ? "S\(seasonNumber) · E\(episodeNumber)  /  \(source.providerName)" : source.providerName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Menu {
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button("Pause in \(minutes) minutes") { sleepDeadline = Date().addingTimeInterval(Double(minutes * 60)) }
                        }
                        if sleepDeadline != nil { Button("Cancel sleep timer", role: .cancel) { sleepDeadline = nil } }
                    } label: {
                        Image(systemName: sleepDeadline == nil ? "moon.zzz" : "moon.zzz.fill")
                            .frame(width: 44, height: 44).cineNexGlass(in: Circle())
                    }.accessibilityLabel("Sleep timer")
                    Menu {
                        Button("Audio, subtitles and playback speed") { isSettingsPresented = true }
                        Toggle("Show transfer information", isOn: $showTransferHUD)
                        Picker("Hide controls after", selection: $controlsDelay) {
                            ForEach([3, 5, 8], id: \.self) { delay in Text("\(delay) seconds").tag(delay) }
                        }
                        Picker("Buffer strategy · next playback", selection: $bufferStrategy) {
                            ForEach(TorrentPlaybackTuning.BufferStrategy.allCases) { strategy in
                                Text(strategy.title).tag(strategy.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .cineNexGlass(in: Circle())
                    }
                    .accessibilityLabel("Playback settings")
                }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .opacity(chrome.isVisible || failure != nil ? 1 : 0)
                .allowsHitTesting(chrome.isVisible || failure != nil)

                if showTransferHUD && isTorrentSource && chrome.isVisible {
                    TorrentTransferBadge().padding(.horizontal, 18).padding(.top, 12)
                }
                if let sleepDeadline {
                    Text("Sleep timer · pauses at \(sleepDeadline.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.white.opacity(0.7)).padding(.top, 10)
                        .opacity(chrome.isVisible ? 1 : 0)
                }
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
                    .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 22))
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
                VStack(spacing: 12) {
                    if isTorrentSource {
                        TorrentBufferingStatusView(playerBufferFraction: Double(player.bufferFill), compact: true)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(player.state == .opening ? "Opening video" : "Buffering video").font(.headline)
                            ProgressView(value: min(1, max(0, Double(player.bufferFill))))
                                .tint(Color.cineNexAccent)
                            Text("Player buffer · \(Int((max(0, min(1, player.bufferFill)) * 100).rounded()))%")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("Receiving media from \(source.providerName). Transfer speed is unavailable for this source.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(20).background(Color.cineNexSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
                    }
                    Button("Choose another release", action: onClose)
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: 370)
                .padding(.horizontal, 20)
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
        .task(id: sleepDeadline) {
            guard let deadline = sleepDeadline else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled else { return }
            player.pause()
            sleepDeadline = nil
            chrome.reveal(autoHide: false)
        }
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
            let stoppingPlayer = player
            Task {
                await stoppingPlayer.stopAndWait()
                PlaybackAudioSession.deactivate()
            }
            nowPlayingController?.end()
            nowPlayingController = nil
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
        resumePosition = resumePlayback && item.kind == .movie
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
                    let cache = isTorrent ? TorrentPlaybackTuning.strategy(bufferStrategy).playerCacheMilliseconds : 1_500
                    media.addOption(":network-caching=\(cache)")
                    if !isTorrent { media.addOption(":http-reconnect") }
                }
                PlaybackDiagnostics.record("Starting VLC media")
                try player.play(media)
                try? player.setPlaybackRate(PlaybackRate(PlaybackPreferences.speed(defaultPlaybackSpeed)))
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
                PlaybackDiagnostics.record("player.state", details: ["state": String(describing: state), "position_seconds": String(positionSeconds)])
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

    private var isTorrentSource: Bool {
        source.url.host == "127.0.0.1" || source.url.host == "localhost"
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
    @AppStorage("cinenex.skipSeconds") private var storedSkipSeconds = 10
    private var skipSeconds: Int { PlaybackPreferences.skipSeconds(storedSkipSeconds) }

    private var sliderPosition: Double {
        min(max(scrubPosition ?? positionSeconds, 0), max(durationSeconds, 1))
    }

    var body: some View {
        CineNexGlassGroup(spacing: 18) {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            HStack(spacing: 24) {
                Button {
                    try? player.seek(by: .seconds(-Double(skipSeconds)), fast: true)
                    onInteraction()
                } label: {
                    Image(systemName: "gobackward.\(skipSeconds)")
                        .font(.system(size: 27, weight: .medium))
                        .frame(width: 52, height: 52)
                        .cineNexGlass(in: Circle())
                }
                .disabled(!player.isSeekable)
                .accessibilityLabel("Back \(skipSeconds) seconds")

                Button {
                    player.togglePlayPause()
                    onInteraction()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 70, height: 70)
                        .cineNexGlass(in: Circle(), prominent: true)
                }
                .accessibilityLabel(player.isPlaying ? "Pause playback" : "Resume playback")

                Button {
                    try? player.seek(by: .seconds(Double(skipSeconds)), fast: true)
                    onInteraction()
                } label: {
                    Image(systemName: "goforward.\(skipSeconds)")
                        .font(.system(size: 27, weight: .medium))
                        .frame(width: 52, height: 52)
                        .cineNexGlass(in: Circle())
                }
                .disabled(!player.isSeekable)
                .accessibilityLabel("Forward \(skipSeconds) seconds")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 20)

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

                Text("−" + timecode(max(0, durationSeconds - (scrubPosition ?? positionSeconds))))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 42, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 620, maxHeight: .infinity)
        }
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
