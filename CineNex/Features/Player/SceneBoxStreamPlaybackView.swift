import AVKit
import SwiftUI
import SwiftVLC

@MainActor
struct SceneBoxStreamPlaybackView: View {
    let source: PlaybackSource
    let item: MediaItem
    let seasonNumber: Int
    let episodeNumber: Int
    let onClose: () -> Void

    @AppStorage("cinenex.preferredSubtitleLanguage") private var preferredSubtitleLanguage = SubtitleLanguage.deviceDefault.code
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

            LinearGradient(
                colors: [.black.opacity(0.78), .clear, .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

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
                        durationSeconds: $durationSeconds
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
                }
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
        .onAppear(perform: startPlayback)
        .onDisappear {
            playbackTask?.cancel()
            monitorTask?.cancel()
            progressTask?.cancel()
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
        player.stop()
        failure = nil

        playbackTask = Task { @MainActor in
            do {
                try await PlaybackAudioSession.activate()
                try Task.checkCancellation()
                try player.play(url: source.url)
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
                    player.pause()
                    return
                }
            }
        }
    }

    private func trackProgress() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                positionSeconds = seconds(player.currentTime)
                durationSeconds = player.duration.map(seconds) ?? 0
                nowPlayingController?.refresh()
            }
        }
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
