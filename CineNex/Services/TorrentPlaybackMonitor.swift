import Combine
import Foundation

/// Values reported by libtorrent, never an invented overall download percentage.
struct TorrentPlaybackSnapshot: Equatable, Sendable {
    enum Stage: String, Sendable {
        case idle, starting, findingPeers, metadata, initialBuffer, ready, buffering, failed, stopped
        var title: String {
            switch self {
            case .idle: return "Preparing playback"
            case .starting: return "Starting the torrent engine"
            case .findingPeers: return "Finding peers"
            case .metadata: return "Receiving video metadata"
            case .initialBuffer: return "Downloading the opening buffer"
            case .ready: return "Video data ready"
            case .buffering: return "Filling the playback buffer"
            case .failed: return "This release could not start"
            case .stopped: return "Playback stopped"
            }
        }
    }
    var stage: Stage = .idle
    var detail = "Connecting to the selected release."
    var downloadBytesPerSecond: UInt64 = 0
    var downloadedBytes: UInt64 = 0
    var peers = 0
    var seeds = 0
    var availablePieces = 0
    var requiredPieces = 0
    var elapsedSeconds: Int = 0
    var sampleDate = Date()

    var bufferFraction: Double? {
        guard requiredPieces > 0 else { return nil }
        return min(1, max(0, Double(availablePieces) / Double(requiredPieces)))
    }
    var speedText: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: downloadBytesPerSecond), countStyle: .binary) + "/s"
    }
    var downloadedText: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: downloadedBytes), countStyle: .binary)
    }
}

/// Only the currently selected engine may publish. Old cancellation/teardown cannot overwrite a new attempt.
@MainActor
final class TorrentPlaybackMonitor: ObservableObject {
    static let shared = TorrentPlaybackMonitor()
    @Published private(set) var snapshot = TorrentPlaybackSnapshot()
    private var owner: UUID?

    func begin(owner: UUID) {
        self.owner = owner
        snapshot = TorrentPlaybackSnapshot(stage: .starting)
    }
    func publish(_ value: TorrentPlaybackSnapshot, owner: UUID) {
        guard self.owner == owner else { return }
        snapshot = value
    }
    func finish(owner: UUID, error: String? = nil) {
        guard self.owner == owner else { return }
        snapshot.stage = error == nil ? .stopped : .failed
        snapshot.detail = error ?? "The torrent session has ended."
        snapshot.downloadBytesPerSecond = 0
        self.owner = nil
    }
}

/// Separate policy so validation measures actual required pieces, including unaligned file boundaries.
enum TorrentStartupReadiness {
    static func counts(required: Set<Int64>, available: [Bool]) -> (ready: Int, total: Int) {
        (required.reduce(0) { count, piece in
            count + (piece >= 0 && piece < Int64(available.count) && available[Int(piece)] ? 1 : 0)
        }, required.count)
    }
}

/// Persisted controls are validated before they influence native playback.
enum TorrentPlaybackTuning {
    enum BufferStrategy: String, CaseIterable, Identifiable {
        case quick, balanced, resilient
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var openingBytes: Int64 {
            switch self { case .quick: return 1_024 * 1_024
            case .balanced: return 2 * 1_024 * 1_024
            case .resilient: return 4 * 1_024 * 1_024 }
        }
        var playerCacheMilliseconds: Int {
            switch self { case .quick: return 750; case .balanced: return 1_500; case .resilient: return 3_000 }
        }
    }
    static func strategy(_ stored: String?) -> BufferStrategy { BufferStrategy(rawValue: stored ?? "") ?? .balanced }
    static func controlsDelay(_ stored: Int) -> Int { [3, 5, 8].contains(stored) ? stored : 5 }
}
