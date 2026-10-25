import Foundation
import LibTorrent

enum XITRIXTorrentFileSupport {
    static func contentType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "mp4": return "video/mp4"
        case "m4v": return "video/x-m4v"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        default: return nil
        }
    }

    static func isPlayableFile(_ path: String) -> Bool {
        contentType(for: path) != nil
    }

    static func safeFileURL(root: URL, relativePath: String) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.unicodeScalars.contains(where: { $0.value == 0 }),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            return nil
        }
        let standardizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = standardizedRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = standardizedRoot.path.hasSuffix("/")
            ? String(standardizedRoot.path.dropLast())
            : standardizedRoot.path
        guard candidate.path.hasPrefix(rootPath + "/") else { return nil }
        return candidate
    }
}

actor XITRIXTorrentPlaybackEngine: TorrentPlaybackEngine, TorrentPieceAvailabilityScheduling {
    private let descriptor: StremioTorrentDescriptor
    private var session: Session?
    private var handle: TorrentHandle?
    private var downloadRoot: URL?
    private var reader: TorrentDiskByteReader?
    private var preparedFile: TorrentPreparedFile?

    init(descriptor: StremioTorrentDescriptor) {
        self.descriptor = descriptor
    }

    func prepareFiles(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile] {
        guard request.isValid else { throw TorrentStreamingError.invalidRequest }
        if let preparedFile { return [preparedFile] }

        guard let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw TorrentStreamingError.engineUnavailable
        }
        let root = cacheDirectory
            .appendingPathComponent("CineNex", isDirectory: true)
            .appendingPathComponent("Torrents", isDirectory: true)
            .appendingPathComponent(descriptor.infoHash, isDirectory: true)
        let torrentsDirectory = root.appendingPathComponent("metadata", isDirectory: true)
        let resumeDirectory = root.appendingPathComponent("resume", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: torrentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resumeDirectory, withIntermediateDirectories: true)

        let settings = Session.Settings()
        settings.agentName = "CineNex"
        settings.maxActiveTorrents = 1
        settings.maxDownloadingTorrents = 1
        settings.maxUploadingTorrents = 1
        settings.isDhtEnabled = true
        settings.isLsdEnabled = false
        settings.isUtpEnabled = true
        settings.preallocateStorage = false
        settings.validateHttpsTrackers = true

        let session = Session(
            root,
            torrentsPath: torrentsDirectory,
            fastResumePath: resumeDirectory,
            settings: settings,
            storages: [:]
        )
        guard let magnet = MagnetURI(with: descriptor.magnetURL) else {
            throw TorrentStreamingError.invalidRequest
        }
        guard let handle = session.addTorrent(magnet) else {
            throw TorrentStreamingError.engineUnavailable
        }

        self.session = session
        self.handle = handle
        self.downloadRoot = root
        session.resume()
        handle.resume()

        let snapshot = try await waitForMetadata(on: handle)
        let selectedFile: FileEntry
        if let requestedIndex = descriptor.fileIndex {
            guard let indexedFile = snapshot.files.first(where: { Int($0.index) == requestedIndex }),
                  XITRIXTorrentFileSupport.isPlayableFile(indexedFile.path) else {
                throw TorrentStreamingError.unsupportedFile
            }
            selectedFile = indexedFile
        } else {
            guard let largestPlayableFile = snapshot.files
                .filter({ $0.size > 0 && XITRIXTorrentFileSupport.isPlayableFile($0.path) })
                .max(by: { $0.size < $1.size }) else {
                throw TorrentStreamingError.unsupportedFile
            }
            selectedFile = largestPlayableFile
        }

        guard selectedFile.size > 0,
              selectedFile.size <= UInt64(Int64.max),
              selectedFile.fileOffset <= UInt64(Int64.max),
              snapshot.pieceLength > 0,
              let contentType = XITRIXTorrentFileSupport.contentType(for: selectedFile.path) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        guard let fileURL = XITRIXTorrentFileSupport.safeFileURL(
            root: root,
            relativePath: selectedFile.path
        ) else {
            throw TorrentStreamingError.unsafeFilePath
        }

        handle.setAllFilesPriority(FileEntry.Priority.lowPriority)
        handle.setFilePriority(FileEntry.Priority.topPriority, at: Int(selectedFile.index))
        handle.setSequentialDownload(true)

        try await waitForFile(at: fileURL, expectedLength: Int64(selectedFile.size))
        guard let verifiedFileURL = XITRIXTorrentFileSupport.safeFileURL(
            root: root,
            relativePath: selectedFile.path
        ), verifiedFileURL == fileURL else {
            throw TorrentStreamingError.unsafeFilePath
        }
        let availability = try TorrentPieceRangeAvailability(
            fileStartOffset: Int64(selectedFile.fileOffset),
            fileLength: Int64(selectedFile.size),
            pieceLength: Int64(snapshot.pieceLength),
            scheduler: self
        )
        let reader = try TorrentDiskByteReader(
            fileURL: verifiedFileURL,
            expectedLength: Int64(selectedFile.size),
            availability: availability
        )
        let prepared = TorrentPreparedFile(
            id: "\(descriptor.id)-\(selectedFile.index)",
            title: request.title,
            fileName: selectedFile.name,
            length: Int64(selectedFile.size),
            contentType: contentType,
            reader: reader
        )
        self.reader = reader
        self.preparedFile = prepared
        return [prepared]
    }

    func prioritize(pieces: Range<Int64>) async throws {
        try Task.checkCancellation()
        guard let handle else { throw TorrentStreamingError.engineUnavailable }
        for piece in pieces {
            try Task.checkCancellation()
            guard piece >= 0,
                  piece <= Int64(Int.max),
                  handle.setPiecePriority(7, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
    }

    func waitUntilAvailable(pieces: Range<Int64>) async throws {
        guard let handle else { throw TorrentStreamingError.engineUnavailable }
        for _ in 0..<360 {
            try Task.checkCancellation()
            handle.updateSnapshot()
            let availablePieces = handle.snapshot.pieces ?? []
            if pieces.allSatisfy({ index in
                index >= 0 &&
                index < Int64(availablePieces.count) &&
                availablePieces[Int(index)].boolValue
            }) {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw TorrentStreamingError.pieceAvailabilityTimeout
    }

    func stop() async {
        if let reader {
            try? await reader.close()
        }
        if let handle, let session {
            handle.pause()
            session.removeTorrent(handle, deleteFiles: true)
        }
        session?.pause()
        if let downloadRoot {
            try? FileManager.default.removeItem(at: downloadRoot)
        }
        self.reader = nil
        self.preparedFile = nil
        self.handle = nil
        self.session = nil
        self.downloadRoot = nil
    }

    private func waitForMetadata(on handle: TorrentHandle) async throws -> TorrentHandle.Snapshot {
        for _ in 0..<240 {
            try Task.checkCancellation()
            handle.updateSnapshot()
            let snapshot = handle.snapshot
            if snapshot.hasMetadata, !snapshot.files.isEmpty {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw TorrentStreamingError.metadataTimeout
    }

    private func waitForFile(at url: URL, expectedLength: Int64) async throws {
        for _ in 0..<120 {
            try Task.checkCancellation()
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber,
               size.int64Value > 0,
               size.int64Value <= expectedLength {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw TorrentStreamingError.torrentFileUnavailable
    }
}
