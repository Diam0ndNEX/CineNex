import Foundation

struct StremioTorrentDescriptor: Equatable, Sendable, Identifiable {
    let infoHash: String
    let fileIndex: Int?
    let magnetURL: URL

    var id: String {
        "\(infoHash):\(fileIndex.map(String.init) ?? "all")"
    }

    init?(infoHash: String?, fileIndex: Int?) {
        guard let infoHash else { return nil }
        let normalizedHash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedHash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            return nil
        }
        if let fileIndex, fileIndex < 0 { return nil }

        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [
            URLQueryItem(name: "xt", value: "urn:btih:\(normalizedHash)")
        ]
        guard let magnetURL = components.url else { return nil }

        self.infoHash = normalizedHash
        self.fileIndex = fileIndex
        self.magnetURL = magnetURL
    }

    init?(stream: StremioStreamEntry) {
        self.init(infoHash: stream.infoHash, fileIndex: stream.fileIndex)
    }
}
