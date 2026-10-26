#if os(iOS)
import MediaPlayer
import SwiftVLC
import UIKit

@MainActor
final class SceneBoxNowPlayingController {
    private let player: SwiftVLC.Player
    private let title: String
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init(player: SwiftVLC.Player, title: String) {
        self.player = player
        self.title = title
    }

    func begin(artworkURL: URL?) {
        end()
        let center = MPRemoteCommandCenter.shared()
        addTarget(to: center.playCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            try? self.player.play()
            self.refresh()
            return .success
        }
        addTarget(to: center.pauseCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player.pause()
            self.refresh()
            return .success
        }
        addTarget(to: center.togglePlayPauseCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player.togglePlayPause()
            self.refresh()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        addTarget(to: center.skipForwardCommand) { [weak self] event in
            guard let self, let skip = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            try? self.player.seek(by: .seconds(skip.interval), fast: true)
            self.refresh()
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        addTarget(to: center.skipBackwardCommand) { [weak self] event in
            guard let self, let skip = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            try? self.player.seek(by: .seconds(-skip.interval), fast: true)
            self.refresh()
            return .success
        }

        addTarget(to: center.changePlaybackPositionCommand) { [weak self] event in
            guard let self, let seek = event as? MPChangePlaybackPositionCommandEvent,
                  seek.positionTime.isFinite else { return .commandFailed }
            try? self.player.seek(to: .seconds(max(0, seek.positionTime)))
            self.refresh()
            return .success
        }

        refresh()
        if let artworkURL { loadArtwork(from: artworkURL) }
    }

    func refresh() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: finiteSeconds(seconds(player.currentTime)),
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0
        ]
        if let duration = player.duration {
            let durationSeconds = seconds(duration)
            if durationSeconds.isFinite, durationSeconds > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
            }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func end() {
        artworkTask?.cancel()
        artworkTask = nil
        for (command, target) in commandTargets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        commandTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func loadArtwork(from url: URL) {
        artworkTask = Task { [weak self] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return }
            guard let self, !Task.isCancelled else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.refresh()
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func finiteSeconds(_ value: Double) -> Double {
        value.isFinite && value >= 0 ? value : 0
    }
}
#endif
