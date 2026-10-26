import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingController {
    private weak var player: AVPlayer?
    private var title = ""
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    func begin(player: AVPlayer, title: String, artworkURL: URL?) {
        end()
        self.player = player
        self.title = title

        let center = MPRemoteCommandCenter.shared()
        addTarget(to: center.playCommand) { [weak self] in
            guard let self, let player = self.player else { return .commandFailed }
            player.play()
            self.refresh()
            return .success
        }
        addTarget(to: center.pauseCommand) { [weak self] in
            guard let self, let player = self.player else { return .commandFailed }
            player.pause()
            self.refresh()
            return .success
        }
        addTarget(to: center.togglePlayPauseCommand) { [weak self] in
            guard let self, let player = self.player else { return .commandFailed }
            if player.rate == 0 {
                player.play()
            } else {
                player.pause()
            }
            self.refresh()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        addTarget(to: center.skipForwardCommand) { [weak self] event in
            guard let self,
                  let player = self.player,
                  let skip = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            let current = player.currentTime().seconds
            guard current.isFinite else { return .commandFailed }
            let duration = player.currentItem?.duration.seconds ?? .infinity
            let target = min(current + skip.interval, duration.isFinite ? duration : current + skip.interval)
            player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600))
            self.refresh()
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        addTarget(to: center.skipBackwardCommand) { [weak self] event in
            guard let self,
                  let player = self.player,
                  let skip = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            let current = player.currentTime().seconds
            guard current.isFinite else { return .commandFailed }
            player.seek(to: CMTime(seconds: max(0, current - skip.interval), preferredTimescale: 600))
            self.refresh()
            return .success
        }

        addTarget(to: center.changePlaybackPositionCommand) { [weak self] event in
            guard let self,
                  let player = self.player,
                  let seek = event as? MPChangePlaybackPositionCommandEvent,
                  seek.positionTime.isFinite else {
                return .commandFailed
            }
            player.seek(to: CMTime(seconds: max(0, seek.positionTime), preferredTimescale: 600))
            self.refresh()
            return .success
        }

        refresh()
        if let artworkURL {
            loadArtwork(from: artworkURL)
        }
    }

    func refresh() {
        guard let player else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: finiteSeconds(player.currentTime().seconds),
            MPNowPlayingInfoPropertyPlaybackRate: player.rate == 0 ? 0.0 : 1.0
        ]
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func end() {
        artworkTask?.cancel()
        artworkTask = nil
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets.removeAll()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = false
        center.pauseCommand.isEnabled = false
        center.togglePlayPauseCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
        player = nil
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
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.refresh()
        }
    }

    private func finiteSeconds(_ value: Double) -> Double {
        value.isFinite && value >= 0 ? value : 0
    }
}
