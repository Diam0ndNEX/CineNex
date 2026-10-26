import Foundation

/// Persists only startup stages, never source URLs, configuration tokens or media names.
enum PlaybackDiagnostics {
    static let storageKey = "cinenex.playbackStartupEvents"

    static var events: [String] { UserDefaults.standard.stringArray(forKey: storageKey) ?? [] }

    static func record(_ stage: String) {
        let event = Date().formatted(.iso8601) + " · " + stage
        UserDefaults.standard.set(Array((events + [event]).suffix(40)), forKey: storageKey)
    }
}
