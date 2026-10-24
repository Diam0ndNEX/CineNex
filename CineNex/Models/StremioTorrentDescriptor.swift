import Foundation

struct StremioTorrentDescriptor: Equatable, Sendable, Identifiable {
    let infoHash: String
    let fileIndex: Int?

    var id: String {
        "\(infoHash):\(fileIndex.map(String.init) ?? "all")"
    }

    var magnetURL: URL {
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [
            URLQueryItem(name: "xt", value: "urn:btih:\(infoHash)")
        ]
        return components.url!
    }

    init?(infoHash: String?, fileIndex: Int?) {
        guard let infoHash else { return nil }
        let normalizedHash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedHash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            return nil
        }
        guard fileIndex == nil || fileIndex! >= 0 else { return nil }
        self.infoHash = normalizedHash
        self.fileIndex = fileIndex
    }

    init?(stream: StremioStreamEntry) {
        self.init(infoHash: stream.infoHash, fileIndex: stream.fileIndex)
    }
}
