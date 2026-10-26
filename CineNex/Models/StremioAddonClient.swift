import Foundation

struct StremioAddonManifest: Decodable, Equatable, Sendable {
    let id: String
    let version: String
    let name: String
    let description: String?
    let resources: [StremioAddonResource]
    let types: [String]
    let idPrefixes: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case name
        case description
        case resources
        case types
        case idPrefixes
    }

    var supportsStreams: Bool {
        resources.contains { $0.name == "stream" }
    }

    func supports(type: String, itemID: String) -> Bool {
        guard types.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) else {
            return false
        }
        return resources.contains { resource in
            switch resource {
            case .named(let name):
                guard name == "stream" else { return false }
                return matches(type: type, itemID: itemID, allowedTypes: nil, allowedPrefixes: idPrefixes)
            case .detailed(let name, let resourceTypes, let resourcePrefixes):
                guard name == "stream" else { return false }
                return matches(
                    type: type,
                    itemID: itemID,
                    allowedTypes: resourceTypes,
                    allowedPrefixes: resourcePrefixes ?? idPrefixes
                )
            }
        }
    }

    private func matches(type: String, itemID: String, allowedTypes: [String]?, allowedPrefixes: [String]?) -> Bool {
        if let allowedTypes, !allowedTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) {
            return false
        }
        guard let allowedPrefixes, !allowedPrefixes.isEmpty else { return true }
        return allowedPrefixes.contains { itemID.hasPrefix($0) }
    }
}

enum StremioAddonResource: Decodable, Equatable, Sendable {
    case named(String)
    case detailed(name: String, types: [String]?, idPrefixes: [String]?)

    private enum CodingKeys: String, CodingKey {
        case name
        case types
        case idPrefixes
    }

    var name: String {
        switch self {
        case .named(let name):
            return name
        case .detailed(let name, _, _):
            return name
        }
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self = .named(value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .detailed(
            name: try container.decode(String.self, forKey: .name),
            types: try container.decodeIfPresent([String].self, forKey: .types),
            idPrefixes: try container.decodeIfPresent([String].self, forKey: .idPrefixes)
        )
    }
}

struct StremioStreamResponse: Decodable, Equatable, Sendable {
    let streams: [StremioStreamEntry]

    private enum CodingKeys: String, CodingKey {
        case streams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var streamContainer = try container.nestedUnkeyedContainer(forKey: .streams)
        var decoded: [StremioStreamEntry] = []
        while !streamContainer.isAtEnd {
            let elementDecoder = try streamContainer.superDecoder()
            if let stream = try? StremioStreamEntry(from: elementDecoder) {
                decoded.append(stream)
            }
        }
        streams = decoded
    }
}

struct StremioStreamEntry: Decodable, Equatable, Sendable, Identifiable {
    let name: String?
    let title: String?
    let url: URL?
    let externalURL: URL?
    let infoHash: String?
    let fileIndex: Int?
    let sources: [String]?
    let description: String?
    let behaviorHints: StremioStreamBehaviorHints?
    let seeders: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case url
        case externalURL = "externalUrl"
        case infoHash
        case fileIndex = "fileIdx"
        case sources
        case description
        case behaviorHints
        case seeders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        let rawURL = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? nil
        let rawExternalURL = (try? container.decodeIfPresent(String.self, forKey: .externalURL)) ?? nil
        url = rawURL.flatMap(URL.init(string:))
        externalURL = rawExternalURL.flatMap(URL.init(string:))
        infoHash = (try? container.decodeIfPresent(String.self, forKey: .infoHash)) ?? nil
        fileIndex = (try? container.decodeIfPresent(Int.self, forKey: .fileIndex)) ?? nil
        sources = (try? container.decodeIfPresent([String].self, forKey: .sources)) ?? nil
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        seeders = (try? container.decodeIfPresent(Int.self, forKey: .seeders)) ?? nil
        behaviorHints = (try? container.decodeIfPresent(StremioStreamBehaviorHints.self, forKey: .behaviorHints)) ?? nil
    }

    var id: String {
        if let url { return url.absoluteString }
        if let infoHash { return "\(infoHash.lowercased()):\(fileIndex.map(String.init) ?? "all")" }
        if let externalURL { return externalURL.absoluteString }
        return [name, title, description].compactMap { $0 }.joined(separator: "|")
    }

    var validatedPlaybackURL: URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}

struct StremioStreamBehaviorHints: Decodable, Equatable, Sendable {
    let notWebReady: Bool?
    let bingeGroup: String?
    let filename: String?
    let videoSize: Int64?

    enum CodingKeys: String, CodingKey {
        case notWebReady
        case bingeGroup
        case filename
        case videoSize
    }
}

enum StremioAddonClientError: LocalizedError, Equatable {
    case invalidManifestURL
    case invalidRequest
    case unsupportedResource
    case invalidResponse
    case httpStatus(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifestURL:
            return "The add-on manifest must be an HTTPS URL without embedded credentials."
        case .invalidRequest:
            return "The stream request needs a supported media type, item ID, and complete episode coordinates for series."
        case .unsupportedResource:
            return "This add-on does not advertise stream support for the requested media ID."
        case .invalidResponse:
            return "The add-on returned an invalid response."
        case .httpStatus(let status):
            return "The add-on returned HTTP status \(status)."
        case .transport(let message):
            return message
        }
    }
}

struct StremioStreamRequest: Equatable, Sendable {
    let mediaType: String
    let itemID: String
    let seasonNumber: Int?
    let episodeNumber: Int?

    init(mediaType: String, itemID: String, seasonNumber: Int? = nil, episodeNumber: Int? = nil) {
        self.mediaType = mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.itemID = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    var isValid: Bool {
        guard ["movie", "series"].contains(mediaType),
              !itemID.isEmpty,
              !itemID.contains("/"),
              !itemID.contains("?"),
              !itemID.contains("#"),
              !itemID.contains("..") else {
            return false
        }
        if mediaType == "movie" {
            return seasonNumber == nil && episodeNumber == nil
        }
        guard let seasonNumber, let episodeNumber else { return false }
        return seasonNumber >= 0 && episodeNumber > 0
    }

    var protocolID: String {
        guard mediaType == "series",
              let seasonNumber,
              let episodeNumber else {
            return itemID
        }
        return "\(itemID):\(seasonNumber):\(episodeNumber)"
    }
}

struct StremioAddonClient: Sendable {
    private let manifestURL: URL
    private let session: URLSession

    init(manifestURL: URL, session: URLSession = .shared) throws {
        guard Self.isSafeHTTPSURL(manifestURL) else {
            throw StremioAddonClientError.invalidManifestURL
        }
        self.manifestURL = manifestURL
        self.session = session
    }

    func fetchManifest() async throws -> StremioAddonManifest {
        try Task.checkCancellation()
        let data = try await fetchData(from: manifestURL)
        try Task.checkCancellation()
        let manifest: StremioAddonManifest
        do {
            manifest = try JSONDecoder().decode(StremioAddonManifest.self, from: data)
        } catch {
            throw StremioAddonClientError.invalidResponse
        }
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StremioAddonClientError.invalidResponse
        }
        return manifest
    }

    func fetchStreams(for request: StremioStreamRequest) async throws -> [StremioStreamEntry] {
        try Task.checkCancellation()
        guard request.isValid else { throw StremioAddonClientError.invalidRequest }
        let manifest = try await fetchManifest()
        try Task.checkCancellation()
        guard manifest.supports(type: request.mediaType, itemID: request.itemID) else {
            throw StremioAddonClientError.unsupportedResource
        }

        let baseURL = manifestURL.deletingLastPathComponent()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let encodedID = request.protocolID.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:"))
        guard let encodedID else { throw StremioAddonClientError.invalidRequest }
        let basePath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        components?.path = "\(basePath)/stream/\(request.mediaType)/\(encodedID).json"
        guard let streamURL = components?.url, Self.isSafeHTTPSURL(streamURL) else {
            throw StremioAddonClientError.invalidManifestURL
        }

        try Task.checkCancellation()
        let data = try await fetchData(from: streamURL)
        try Task.checkCancellation()
        let response: StremioStreamResponse
        do {
            response = try JSONDecoder().decode(StremioStreamResponse.self, from: data)
        } catch {
            throw StremioAddonClientError.invalidResponse
        }
        PlaybackDiagnostics.record("addon.streams.parsed", details: [
            "host": manifestURL.host ?? "unknown",
            "entry_count": String(response.streams.count),
            "hash_entries": String(response.streams.filter { $0.infoHash != nil }.count),
            "direct_candidates": String(response.streams.filter { $0.validatedPlaybackURL != nil }.count)
        ])
        return response.streams
    }

    private func fetchData(from url: URL) async throws -> Data {
        let startedAt = Date()
        let host = url.host ?? "unknown"
        let resource = url.path.contains("/stream/") ? "stream" : "manifest"
        PlaybackDiagnostics.record("addon.http.begin", details: ["host": host, "resource": resource])
        try Task.checkCancellation()
        guard Self.isSafeHTTPSURL(url) else { throw StremioAddonClientError.invalidManifestURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = url.path.contains("/stream/") ? 25 : 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let redirectDelegate = StremioHTTPSRedirectDelegate()
        do {
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StremioAddonClientError.invalidResponse
            }
            guard let finalURL = httpResponse.url, Self.isSafeHTTPSURL(finalURL) else {
                throw StremioAddonClientError.invalidManifestURL
            }
            PlaybackDiagnostics.record("addon.http.response", details: [
                "host": host, "resource": resource, "http": String(httpResponse.statusCode),
                "bytes": String(data.count), "elapsed_ms": String(Int(Date().timeIntervalSince(startedAt) * 1000))
            ])
            if (300..<400).contains(httpResponse.statusCode) {
                throw StremioAddonClientError.invalidManifestURL
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw StremioAddonClientError.httpStatus(httpResponse.statusCode)
            }
            guard data.count <= 2_000_000 else {
                throw StremioAddonClientError.invalidResponse
            }
            return data
        } catch let error as StremioAddonClientError {
            PlaybackDiagnostics.record("addon.http.rejected", details: ["host": host, "resource": resource, "reason": error.localizedDescription])
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            PlaybackDiagnostics.record("addon.http.transport_error", details: ["host": host, "resource": resource, "domain": (error as NSError).domain, "code": String((error as NSError).code)])
            throw StremioAddonClientError.transport(error.localizedDescription)
        }
    }

    static func isSafeHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
    }
}
final class StremioHTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, StremioAddonClient.isSafeHTTPSURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

