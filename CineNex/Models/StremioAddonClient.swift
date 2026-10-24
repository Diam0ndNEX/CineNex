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
}

struct StremioStreamEntry: Decodable, Equatable, Sendable, Identifiable {
    let name: String?
    let title: String?
    let url: URL?
    let externalURL: URL?
    let infoHash: String?
    let fileIndex: Int?
    let description: String?
    let behaviorHints: StremioStreamBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case url
        case externalURL = "externalUrl"
        case infoHash
        case fileIndex = "fileIdx"
        case description
        case behaviorHints
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
    private let decoder: JSONDecoder

    init(manifestURL: URL, session: URLSession = .shared) throws {
        guard Self.isSafeHTTPSURL(manifestURL) else {
            throw StremioAddonClientError.invalidManifestURL
        }
        self.manifestURL = manifestURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchManifest() async throws -> StremioAddonManifest {
        let data = try await fetchData(from: manifestURL)
        let manifest: StremioAddonManifest
        do {
            manifest = try decoder.decode(StremioAddonManifest.self, from: data)
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
        guard request.isValid else { throw StremioAddonClientError.invalidRequest }
        let manifest = try await fetchManifest()
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

        let data = try await fetchData(from: streamURL)
        let response: StremioStreamResponse
        do {
            response = try decoder.decode(StremioStreamResponse.self, from: data)
        } catch {
            throw StremioAddonClientError.invalidResponse
        }
        return response.streams
    }

    private func fetchData(from url: URL) async throws -> Data {
        guard Self.isSafeHTTPSURL(url) else { throw StremioAddonClientError.invalidManifestURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StremioAddonClientError.invalidResponse
            }
            guard let finalURL = httpResponse.url, Self.isSafeHTTPSURL(finalURL) else {
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
            throw error
        } catch {
            throw StremioAddonClientError.transport(error.localizedDescription)
        }
    }

    private static func isSafeHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
    }
}
