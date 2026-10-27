import Foundation

enum TorrentTransferProfile: String, CaseIterable, Identifiable {
    case balanced, economy, unlimited
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Native wrapper expects bytes per second; zero means unlimited.
    var downloadBytesPerSecond: UInt {
        switch self { case .balanced: return 12 * 1_024 * 1_024
        case .economy: return 4 * 1_024 * 1_024
        case .unlimited: return 0 }
    }
    var uploadBytesPerSecond: UInt { self == .unlimited ? 0 : 256 * 1_024 }
    var detail: String {
        switch self {
        case .balanced: return "Up to 12 MiB/s download and 256 KiB/s upload. A balanced transfer ceiling for playback."
        case .economy: return "Up to 4 MiB/s download and 256 KiB/s upload. Large high-bitrate releases may buffer."
        case .unlimited: return "No transfer-rate ceiling. May increase network, storage and energy use."
        }
    }
}

enum PlaybackPreferences {
    static func skipSeconds(_ stored: Int) -> Int { [10, 15, 30].contains(stored) ? stored : 10 }
    static func speed(_ stored: Double) -> Float { [0.75, 1, 1.25, 1.5, 2].contains(stored) ? Float(stored) : 1 }
}
