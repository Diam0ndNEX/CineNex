import Foundation

/// Adapted from SceneBox's DefaultTrackers and LibtorrentSession initializer.
/// Keep descriptor-specific trackers first, then provide discovery fallbacks.
enum SceneBoxTorrentBootstrap {
    private static let defaultTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.tracker.cl:1337/announce",
        "udp://tracker.openbittorrent.com:6969/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://open.demonii.com:6969/announce",
        "udp://tracker.dler.org:6969/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.tiny-vps.com:6969/announce",
        "udp://explodie.org:6969/announce",
        "udp://tracker-udp.gbitt.info:80/announce",
        "udp://tracker.moeking.me:6969/announce"
    ].compactMap(URL.init(string:))

    static func withDefaultTrackers(_ descriptor: StremioTorrentDescriptor) -> StremioTorrentDescriptor? {
        StremioTorrentDescriptor(
            infoHash: descriptor.infoHash,
            fileIndex: descriptor.fileIndex,
            trackers: descriptor.trackers + defaultTrackers,
            title: descriptor.title,
            providerName: descriptor.providerName
        )
    }
}
