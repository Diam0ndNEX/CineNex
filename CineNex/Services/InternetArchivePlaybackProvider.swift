import Foundation

struct InternetArchivePlaybackProvider: PlaybackSourceProvider, Sendable {
    let id = "internet-archive"
    let displayName = "Internet Archive"
    let priority = 50

    private let session: URLSession
    private let apiBaseURL: URL

    init(
        session: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://archive.org")!
    ) {
        self.session = session
        self.apiBaseURL = apiBaseURL
    }

    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource] {
        guard request.isValid, request.mediaKind == .movie else { return [] }

        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("advancedsearch.php"),
            resolvingAgainstBaseURL: false
        )
        let escapedTitle = request.title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "title:\"\(escapedTitle)\" AND mediatype:movies"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "year"),
            URLQueryItem(name: "rows", value: "8"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "output", value: "json")
        ]

        guard let searchURL = components?.url else {
            throw InternetArchiveProviderError.invalidSearchURL
        }

        let searchData = try await data(from: searchURL)
        let records = try Self.searchRecords(from: searchData)
            .filter { record in
                Self.normalizedTitle(record.title) == Self.normalizedTitle(request.title)
                    && (request.releaseYear == nil || record.year == nil || record.year == request.releaseYear)
            }
            .prefix(4)

        return await withTaskGroup(of: [PlaybackSource].self, returning: [PlaybackSource].self) { group in
            for record in records {
                group.addTask {
                    do {
                        let metadataURL = apiBaseURL
                            .appendingPathComponent("metadata")
                            .appendingPathComponent(record.identifier)
                        let metadataData = try await data(from: metadataURL)
                        let object = try Self.jsonObject(from: metadataData)
                        return Self.sources(
                            fromMetadataResponse: object,
                            identifier: record.identifier,
                            request: request
                        )
                    } catch {
                        return []
                    }
                }
            }

            var collected: [PlaybackSource] = []
            for await sources in group {
                collected.append(contentsOf: sources)
            }
            var seen = Set<String>()
            return collected
                .filter { seen.insert($0.url.absoluteString).inserted }
                .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        }
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("CineNex/1.0 (iOS media discovery)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw InternetArchiveProviderError.invalidResponse
        }
        return data
    }

    private static func searchRecords(from data: Data) throws -> [ArchiveSearchRecord] {
        let object = try jsonObject(from: data)
        guard let response = object["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else {
            throw InternetArchiveProviderError.invalidSearchResponse
        }
        return docs.compactMap { doc in
            guard let identifier = doc["identifier"] as? String,
                  isSafeIdentifier(identifier),
                  let title = doc["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let year: Int?
            if let value = doc["year"] as? Int {
                year = value
            } else if let value = doc["year"] as? String {
                year = Int(value)
            } else {
                year = nil
            }
            return ArchiveSearchRecord(identifier: identifier, title: title, year: year)
        }
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InternetArchiveProviderError.invalidJSON
        }
        return object
    }

    static func sources(
        fromMetadataResponse object: [String: Any],
        identifier: String,
        request: PlaybackSourceRequest
    ) -> [PlaybackSource] {
        guard request.isValid,
              request.mediaKind == .movie,
              isSafeIdentifier(identifier),
              let metadata = object["metadata"] as? [String: Any],
              let title = metadata["title"] as? String,
              normalizedTitle(title) == normalizedTitle(request.title),
              isAllowedLicense(metadata["licenseurl"] as? String),
              let files = object["files"] as? [[String: Any]] else {
            return []
        }

        let metadataYear: Int?
        if let value = metadata["year"] as? Int {
            metadataYear = value
        } else if let value = metadata["year"] as? String {
            metadataYear = Int(value)
        } else {
            metadataYear = nil
        }
        if let requestedYear = request.releaseYear,
           let metadataYear,
           requestedYear != metadataYear {
            return []
        }

        return files.compactMap { file in
            guard let name = file["name"] as? String,
                  isSafeFilename(name),
                  name.lowercased().hasSuffix(".mp4"),
                  let format = file["format"] as? String,
                  isSupportedVideoFormat(format),
                  !isPrivate(file["private"]) else {
                return nil
            }

            let encodedIdentifier = pathSegment(identifier)
            let encodedFilename = pathSegment(name)
            guard let url = URL(string: "https://archive.org/download/\(encodedIdentifier)/\(encodedFilename)"),
                  url.scheme == "https",
                  url.host == "archive.org" else {
                return nil
            }

            return PlaybackSource(
                id: "internet-archive-\(identifier)-\(name)",
                providerID: "internet-archive",
                providerName: "Internet Archive",
                title: title,
                url: url,
                qualityLabel: "MP4 · Public domain/CC",
                languageCode: nil,
                subtitleLanguages: [],
                supportsNativePlayback: true,
                providerPriority: 50
            )
        }
    }

    static func isAllowedLicense(_ licenseURL: String?) -> Bool {
        guard let licenseURL,
              let components = URLComponents(string: licenseURL),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "creativecommons.org" else {
            return false
        }

        let path = components.path.lowercased()
        guard !path.contains(".."),
              components.query == nil,
              components.fragment == nil else {
            return false
        }
        return path.hasPrefix("/publicdomain/zero/")
            || path.hasPrefix("/publicdomain/mark/")
    }

    private static func isSupportedVideoFormat(_ format: String) -> Bool {
        let normalized = format.lowercased()
        return normalized.contains("mpeg4")
            || normalized.contains("mpeg-4")
            || normalized.contains("h.264")
            || normalized == "mp4"
    }

    private static func isPrivate(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let string = value as? String {
            return ["true", "1", "yes"].contains(string.lowercased())
        }
        return false
    }

    private static func isSafeIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty
            && identifier.count <= 180
            && identifier.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename.count <= 240
            && !filename.contains("/")
            && !filename.contains("\\")
            && filename != "."
            && filename != ".."
            && !filename.contains("?")
            && !filename.contains("#")
    }

    private static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }
}

private struct ArchiveSearchRecord: Sendable {
    let identifier: String
    let title: String
    let year: Int?
}

enum InternetArchiveProviderError: LocalizedError {
    case invalidSearchURL
    case invalidResponse
    case invalidJSON
    case invalidSearchResponse

    var errorDescription: String? {
        switch self {
        case .invalidSearchURL:
            return "Internet Archive search could not be prepared."
        case .invalidResponse:
            return "Internet Archive returned an unsuccessful response."
        case .invalidJSON:
            return "Internet Archive returned malformed JSON."
        case .invalidSearchResponse:
            return "Internet Archive returned an unexpected search response."
        }
    }
}
