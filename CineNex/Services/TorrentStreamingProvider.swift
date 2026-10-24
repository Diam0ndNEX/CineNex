import Foundation
import Network
import Security

protocol TorrentByteReader: Sendable {
    func read(offset: Int64, length: Int) async throws -> Data
}

struct TorrentPreparedFile: Sendable {
    let id: String
    let title: String
    let fileName: String
    let length: Int64
    let contentType: String
    let reader: any TorrentByteReader

    var isValid: Bool {
        !id.isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        length > 0 &&
        !contentType.contains("\r") &&
        !contentType.contains("\n")
    }
}

protocol TorrentPlaybackEngine: Sendable {
    func prepareFiles(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile]
    func stop() async
}

enum TorrentStreamingError: LocalizedError, Equatable {
    case invalidRequest
    case listenerUnavailable
    case invalidHTTPRequest
    case unauthorized
    case fileUnavailable
    case invalidRead
    case engineUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "The torrent playback request is invalid."
        case .listenerUnavailable: return "The local playback server could not start."
        case .invalidHTTPRequest: return "The local playback request is malformed."
        case .unauthorized: return "The local playback URL is invalid or expired."
        case .fileUnavailable: return "The requested torrent file is no longer available."
        case .invalidRead: return "The torrent engine returned an invalid byte range."
        case .engineUnavailable: return "The torrent playback engine is not configured."
        }
    }
}

struct TorrentHTTPRequest: Equatable, Sendable {
    let method: String
    let target: String
    let headers: [String: String]

    static let maximumHeaderBytes = 16 * 1024

    static func parse(_ data: Data) throws -> TorrentHTTPRequest {
        guard data.count <= maximumHeaderBytes,
              let text = String(data: data, encoding: .utf8),
              text.hasSuffix("\r\n\r\n"),
              !text.contains("\0") else {
            throw TorrentStreamingError.invalidHTTPRequest
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw TorrentStreamingError.invalidHTTPRequest }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              parts[2] == "HTTP/1.0" || parts[2] == "HTTP/1.1",
              parts[1].hasPrefix("/"),
              !parts[1].contains("#"),
              !parts[1].contains("\\"),
              parts[0].utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              parts[1].utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw TorrentStreamingError.invalidHTTPRequest
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard !line.hasPrefix(" ") && !line.hasPrefix("\t"),
                  let colon = line.firstIndex(of: ":") else {
                throw TorrentStreamingError.invalidHTTPRequest
            }
            let name = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let tokenCharacters = "!#$%&'*+-.^_|~".utf8
            guard !name.isEmpty,
                  name.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 122) || tokenCharacters.contains($0) }),
                  value.utf8.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) }),
                  headers[name] == nil else {
                throw TorrentStreamingError.invalidHTTPRequest
            }
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil {
            throw TorrentStreamingError.invalidHTTPRequest
        }
        if let contentLength = headers["content-length"], contentLength != "0" {
            throw TorrentStreamingError.invalidHTTPRequest
        }
        if parts[2] == "HTTP/1.1", headers["host"]?.isEmpty != false {
            throw TorrentStreamingError.invalidHTTPRequest
        }
        return TorrentHTTPRequest(method: String(parts[0]), target: String(parts[1]), headers: headers)
    }
}

private final class TorrentContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func claim() -> Bool {
        lock.withLock {
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }
}

final class TorrentLoopbackHTTPServer: @unchecked Sendable {
    private struct Resource {
        let file: TorrentPreparedFile
        let registeredAt: Date
    }

    private static let resourceLifetime: TimeInterval = 2 * 60 * 60
    private static let maximumResources = 64

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.diam0ndnex.cinenex.torrent-http", qos: .userInitiated)
    private var listener: NWListener?
    private var resources: [String: Resource] = [:]
    private var bearerToken = ""
    private var started = false
    private var stopped = false

    func start() async throws -> UInt16 {
        let state = lock.withLock { (started, stopped, listener?.port?.rawValue) }
        if state.0, let port = state.2 { return port }
        guard !state.1 else { throw TorrentStreamingError.listenerUnavailable }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters)
        } catch {
            throw TorrentStreamingError.listenerUnavailable
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let gate = TorrentContinuationGate()
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    if let port = newListener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: TorrentStreamingError.listenerUnavailable)
                    }
                case .failed, .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: TorrentStreamingError.listenerUnavailable)
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                self.queue.async {
                    Task { await self.handle(connection) }
                }
            }
            newListener.start(queue: queue)
        }

        let accepted = lock.withLock {
            guard !stopped else { return false }
            listener = newListener
            bearerToken = Self.makeToken()
            started = true
            return true
        }
        guard accepted else {
            newListener.cancel()
            throw TorrentStreamingError.listenerUnavailable
        }
        return port
    }

    func register(_ file: TorrentPreparedFile) throws -> URL {
        guard file.isValid else { throw TorrentStreamingError.fileUnavailable }
        lock.lock()
        guard !stopped, started, let port = listener?.port?.rawValue, !bearerToken.isEmpty else {
            lock.unlock()
            throw TorrentStreamingError.listenerUnavailable
        }
        let token = bearerToken
        let now = Date()
        resources = resources.filter { now.timeIntervalSince($0.value.registeredAt) < Self.resourceLifetime }
        guard resources.count < Self.maximumResources else {
            lock.unlock()
            throw TorrentStreamingError.fileUnavailable
        }
        let resourceID = Self.makeToken()
        resources[resourceID] = Resource(file: file, registeredAt: now)
        lock.unlock()

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/v1/\(token)/\(resourceID)"
        guard let url = components.url else {
            lock.lock()
            resources.removeValue(forKey: resourceID)
            lock.unlock()
            throw TorrentStreamingError.listenerUnavailable
        }
        return url
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        resources.removeAll()
        bearerToken = ""
        let currentListener = listener
        listener = nil
        lock.unlock()
        currentListener?.cancel()
    }

    private func handle(_ connection: NWConnection) async {
        defer { connection.cancel() }
        let request: TorrentHTTPRequest
        let file: TorrentPreparedFile
        do {
            request = try TorrentHTTPRequest.parse(await receiveHeader(from: connection))
            file = try resolve(request.target)
        } catch {
            let status = (error as? TorrentStreamingError) == .unauthorized ? 404 : 400
            try? await send(Self.errorResponse(status: status), connection: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            let plan = TorrentHTTPResponsePlan.make(
                method: request.method,
                rangeHeader: nil,
                totalLength: file.length,
                contentType: file.contentType
            )
            try? await send(Self.serialize(status: plan.statusCode, headers: plan.headers), connection: connection)
            return
        }

        let plan = TorrentHTTPResponsePlan.make(
            method: request.method,
            rangeHeader: request.headers["range"],
            totalLength: file.length,
            contentType: file.contentType
        )
        do {
            try await send(plan: plan, connection: connection, file: file)
        } catch {
            connection.cancel()
        }
    }

    private func resolve(_ target: String) throws -> TorrentPreparedFile {
        guard let components = URLComponents(string: target),
              components.query == nil,
              components.fragment == nil else {
            throw TorrentStreamingError.unauthorized
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[0] == "v1" else { throw TorrentStreamingError.unauthorized }
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, parts[1] == bearerToken, let resource = resources[parts[2]] else {
            throw TorrentStreamingError.unauthorized
        }
        guard Date().timeIntervalSince(resource.registeredAt) < Self.resourceLifetime else {
            resources.removeValue(forKey: parts[2])
            throw TorrentStreamingError.unauthorized
        }
        return resource.file
    }

    private func receiveHeader(from connection: NWConnection) async throws -> Data {
        var accumulated = Data()
        while accumulated.count <= TorrentHTTPRequest.maximumHeaderBytes {
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: TorrentStreamingError.invalidHTTPRequest)
                    } else {
                        continuation.resume(throwing: TorrentStreamingError.invalidHTTPRequest)
                    }
                }
            }
            accumulated.append(chunk)
            if let marker = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                guard marker.upperBound == accumulated.endIndex else {
                    throw TorrentStreamingError.invalidHTTPRequest
                }
                return accumulated
            }
        }
        throw TorrentStreamingError.invalidHTTPRequest
    }

    private func send(plan: TorrentHTTPResponsePlan, connection: NWConnection, file: TorrentPreparedFile) async throws {
        try await send(Self.serialize(status: plan.statusCode, headers: plan.headers), connection: connection)
        guard plan.sendsBody, let range = plan.bodyRange else { return }
        var offset = range.lowerBound
        let chunkLimit = 128 * 1024
        while offset <= range.upperBound {
            try Task.checkCancellation()
            let length = Int(min(Int64(chunkLimit), range.upperBound - offset + 1))
            let data = try await file.reader.read(offset: offset, length: length)
            guard data.count == length else { throw TorrentStreamingError.invalidRead }
            try await send(data, connection: connection)
            offset += Int64(data.count)
        }
    }

    private func send(_ data: Data, connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private static func serialize(status: Int, headers: [String: String]) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 206: reason = "Partial Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 416: reason = "Range Not Satisfiable"
        default: reason = "Internal Server Error"
        }
        var lines = ["HTTP/1.1 \(status) \(reason)"]
        for (name, value) in headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            guard !name.contains("\r"), !name.contains("\n"), !value.contains("\r"), !value.contains("\n") else { continue }
            lines.append("\(name): \(value)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private static func errorResponse(status: Int) -> Data {
        serialize(status: status, headers: [
            "Content-Length": "0",
            "Connection": "close",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff"
        ])
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct TorrentPlaybackProvider: PlaybackSourceProvider, Sendable {
    let id: String
    let displayName: String
    let priority: Int
    private let engine: any TorrentPlaybackEngine
    private let server: TorrentLoopbackHTTPServer

    init(
        id: String = "libtorrent",
        displayName: String = "Torrent streaming",
        priority: Int = 40,
        engine: any TorrentPlaybackEngine,
        server: TorrentLoopbackHTTPServer = TorrentLoopbackHTTPServer()
    ) {
        self.id = id
        self.displayName = displayName
        self.priority = priority
        self.engine = engine
        self.server = server
    }

    func findSources(for request: PlaybackSourceRequest) async throws -> [PlaybackSource] {
        guard request.isValid else { throw PlaybackSourceSearchError.invalidRequest }
        let preparedFiles = try await engine.prepareFiles(for: request)
            .filter(\.isValid)
            .sorted { lhs, rhs in
                if lhs.length != rhs.length { return lhs.length > rhs.length }
                return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            }
        guard !preparedFiles.isEmpty else { return [] }
        _ = try await server.start()
        var sources: [PlaybackSource] = []
        for file in preparedFiles {
            let url = try server.register(file)
            sources.append(PlaybackSource(
                id: "\(file.id)-\(UUID().uuidString)",
                providerID: id,
                providerName: displayName,
                title: file.title,
                url: url,
                qualityLabel: nil,
                languageCode: nil,
                subtitleLanguages: [],
                supportsNativePlayback: true,
                providerPriority: priority
            ))
        }
        return sources
    }

    func stop() async {
        server.stop()
        await engine.stop()
    }
}
