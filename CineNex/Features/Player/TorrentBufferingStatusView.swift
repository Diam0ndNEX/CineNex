import SwiftUI

/// Can be embedded both in the release preparation screen and over the player.
@MainActor
struct TorrentBufferingStatusView: View {
    @ObservedObject private var monitor = TorrentPlaybackMonitor.shared
    var playerBufferFraction: Double? = nil
    var compact = false
    private var snapshot: TorrentPlaybackSnapshot { monitor.snapshot }
    private var fraction: Double? {
        if let value = playerBufferFraction, value.isFinite { return min(1, max(0, value)) }
        return snapshot.bufferFraction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: snapshot.peers > 0 ? "network" : "antenna.radiowaves.left.and.right")
                    .font(.title3).foregroundStyle(Color.cineNexAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playerBufferFraction == nil ? snapshot.stage.title : "Buffering video")
                        .font(.headline)
                    Text(snapshot.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if snapshot.elapsedSeconds > 0 {
                    Text("\(snapshot.elapsedSeconds)s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let fraction {
                ProgressView(value: fraction).tint(Color.cineNexAccent)
                    .accessibilityLabel(playerBufferFraction == nil ? "Verified buffer pieces" : "Player buffer")
                Text(playerBufferFraction == nil
                     ? "\(snapshot.availablePieces) of \(snapshot.requiredPieces) buffer pieces verified"
                     : "Player buffer · \(Int((fraction * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Color.cineNexAccent)
                    .accessibilityLabel(snapshot.stage.title)
            }
            HStack(spacing: 18) {
                metric("Download", snapshot.speedText)
                metric("Received", snapshot.downloadedText)
                metric("Peers", "\(snapshot.peers)")
                metric("Seeds", "\(snapshot.seeds)")
            }
            if snapshot.peers == 0, snapshot.elapsedSeconds >= 8 {
                Text("No peers have connected yet. Another release may start sooner.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(compact ? 16 : 20)
        .background(Color.cineNexSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}


@MainActor
struct TorrentTransferBadge: View {
    @ObservedObject private var monitor = TorrentPlaybackMonitor.shared
    var body: some View {
        HStack(spacing: 12) {
            Label(monitor.snapshot.speedText, systemImage: "arrow.down")
            Text("\(monitor.snapshot.peers) peers")
            Text("\(monitor.snapshot.seeds) seeds")
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
        .shadow(color: .black, radius: 3, y: 1)
        .accessibilityElement(children: .combine)
    }
}
