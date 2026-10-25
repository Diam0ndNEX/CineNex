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


struct TorrentStartupPiecePriorityPlan: Equatable {
    let priorities: [Int64: Int]

    static func make(
        fileStartOffset: Int64,
        fileLength: Int64,
        pieceLength: Int64,
        pieceCount: Int64,
        headBytes: Int64 = 2 * 1_024 * 1_024,
        tailBytes: Int64 = 16 * 1_024 * 1_024,
        headPriority: Int = 7,
        tailPriority: Int = 5
    ) -> TorrentStartupPiecePriorityPlan? {
        guard fileStartOffset >= 0,
              fileLength >= 0,
              pieceLength > 0,
              pieceCount >= 0,
              headBytes >= 0,
              tailBytes >= 0,
              (0...7).contains(headPriority),
              (0...7).contains(tailPriority) else {
            return nil
        }

        let (fileEnd, overflow) = fileStartOffset.addingReportingOverflow(fileLength)
        guard !overflow else { return nil }
        guard fileLength == 0 else {
            let lastPiece = (fileEnd - 1) / pieceLength
            guard lastPiece < pieceCount else { return nil }
            var priorities: [Int64: Int] = [:]

            func addRange(start: Int64, end: Int64, priority: Int) {
                guard end > start else { return }
                let firstPiece = start / pieceLength
                let lastPiece = (end - 1) / pieceLength
                for piece in firstPiece...lastPiece {
                    priorities[piece] = max(priorities[piece] ?? 0, priority)
                }
            }

            let headEnd = min(fileEnd, fileStartOffset + min(headBytes, fileLength))
            addRange(start: fileStartOffset, end: headEnd, priority: headPriority)
            let tailStart = max(fileStartOffset, fileEnd - min(tailBytes, fileLength))
            addRange(start: tailStart, end: fileEnd, priority: tailPriority)
            return TorrentStartupPiecePriorityPlan(priorities: priorities)
        }
        return TorrentStartupPiecePriorityPlan(priorities: [:])
    }
}

struct TorrentPieceDeadlinePlan: Equatable {
    let deadlinesMilliseconds: [Int64: Int]

    static func make(
        for requested: Range<Int64>,
        pieceCount: Int64,
        stepMilliseconds: Int = 80,
        maximumMilliseconds: Int = 60_000
    ) -> TorrentPieceDeadlinePlan? {
        guard pieceCount >= 0,
              requested.lowerBound >= 0,
              requested.upperBound >= requested.lowerBound,
              requested.upperBound <= pieceCount,
              stepMilliseconds >= 0,
              maximumMilliseconds >= 0 else {
            return nil
        }

        var deadlines: [Int64: Int] = [:]
        var deadline = 0
        for piece in requested {
            deadlines[piece] = deadline
            let remainingDelay = maximumMilliseconds - deadline
            deadline = stepMilliseconds >= remainingDelay
                ? maximumMilliseconds
                : deadline + stepMilliseconds
        }
        return TorrentPieceDeadlinePlan(deadlinesMilliseconds: deadlines)
    }
}

struct TorrentPiecePriorityWindow: Equatable {
    let piecesToDemote: [Int64]
    let piecesToPromote: [Int64]

    static func expandedRange(
        for requested: Range<Int64>,
        pieceCount: Int64,
        lookBehind: Int64 = 2,
        lookAhead: Int64 = 24
    ) -> Range<Int64>? {
        guard pieceCount >= 0,
              lookBehind >= 0,
              lookAhead >= 0,
              requested.lowerBound >= 0,
              requested.upperBound >= requested.lowerBound,
              requested.upperBound <= pieceCount else {
            return nil
        }
        guard !requested.isEmpty else { return requested }

        let lowerBound = requested.lowerBound > lookBehind
            ? requested.lowerBound - lookBehind
            : 0
        let remainingPieces = pieceCount - requested.upperBound
        let upperBound = requested.upperBound + min(lookAhead, remainingPieces)
        return lowerBound..<upperBound
    }

    init(current: Set<Int64>, requested: Set<Int64>) {
        piecesToDemote = current.subtracting(requested).sorted()
        piecesToPromote = requested.subtracting(current).sorted()
    }
}

actor XITRIXTorrentPlaybackEngine: TorrentPlaybackEngine, TorrentPieceAvailabilityScheduling {
    private let descriptor: StremioTorrentDescriptor
    private var session: Session?
    private var handle: TorrentHandle?
    private var downloadRoot: URL?
    private var reader: TorrentDiskByteReader?
    private var preparedFile: TorrentPreparedFile?
    private var prioritizedPieces = Set<Int64>()
    private var startupPiecePriorities: [Int64: Int] = [:]
    private var deadlinePieces = Set<Int64>()

    init(descriptor: StremioTorrentDescriptor) {
        self.descriptor = descriptor
    }

    func prepareFiles(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile] {
        guard request.isValid else { throw TorrentStreamingError.invalidRequest }
        if let preparedFile { return [preparedFile] }

        do {
            return try await prepareFilesInternal(for: request)
        } catch {
            await stop()
            throw error
        }
    }

    private func prepareFilesInternal(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile] {

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

        let selectedFileIndex = Int(selectedFile.index)
        let otherFileIndexes = snapshot.files
            .map { Int($0.index) }
            .filter { $0 != selectedFileIndex }
        if !otherFileIndexes.isEmpty {
            handle.setFilesPriority(
                FileEntry.Priority.dontDownload,
                at: otherFileIndexes.map { NSNumber(value: $0) }
            )
        }
        handle.setFilePriority(FileEntry.Priority.lowPriority, at: selectedFileIndex)

        handle.updateSnapshot()
        guard let pieceStates = handle.snapshot.pieces,
              let startupPlan = TorrentStartupPiecePriorityPlan.make(
                fileStartOffset: Int64(selectedFile.fileOffset),
                fileLength: Int64(selectedFile.size),
                pieceLength: Int64(snapshot.pieceLength),
                pieceCount: Int64(pieceStates.count)
              ) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        for (piece, priority) in startupPlan.priorities.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            guard handle.setPiecePriority(priority, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
        startupPiecePriorities = startupPlan.priorities

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
        guard !pieces.isEmpty else { return }

        handle.updateSnapshot()
        guard let pieceStates = handle.snapshot.pieces else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        let pieceCount = Int64(pieceStates.count)
        guard pieceCount <= Int64(Int.max),
              pieces.lowerBound >= 0,
              pieces.upperBound >= pieces.lowerBound,
              pieces.upperBound <= pieceCount,
              let expandedRange = TorrentPiecePriorityWindow.expandedRange(
                for: pieces,
                pieceCount: pieceCount
              ) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        let requestedPieces = Set(expandedRange)
        guard let deadlinePlan = TorrentPieceDeadlinePlan.make(
            for: pieces,
            pieceCount: pieceCount
        ) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        let requestedDeadlinePieces = Set(deadlinePlan.deadlinesMilliseconds.keys)

        for piece in deadlinePieces.subtracting(requestedDeadlinePieces).sorted() {
            try Task.checkCancellation()
            guard handle.clearPieceDeadline(at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
        for (piece, milliseconds) in deadlinePlan.deadlinesMilliseconds.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            guard handle.setPieceDeadline(milliseconds, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }

        let priorityWindow = TorrentPiecePriorityWindow(current: prioritizedPieces, requested: requestedPieces)
        for piece in priorityWindow.piecesToDemote {
            try Task.checkCancellation()
            let fallbackPriority = startupPiecePriorities[piece] ?? 1
            guard handle.setPiecePriority(fallbackPriority, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
        for piece in priorityWindow.piecesToPromote {
            try Task.checkCancellation()
            guard handle.setPiecePriority(7, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
        prioritizedPieces = requestedPieces
        deadlinePieces = requestedDeadlinePieces
    }

    func waitUntilAvailable(pieces: Range<Int64>) async throws {
        guard let handle else { throw TorrentStreamingError.engineUnavailable }
        guard !pieces.isEmpty else { return }
        handle.updateSnapshot()
        guard let initialPieceStates = handle.snapshot.pieces,
              pieces.allSatisfy({ $0 >= 0 && $0 < Int64(initialPieceStates.count) }) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
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
        self.prioritizedPieces.removeAll()
        self.startupPiecePriorities.removeAll()
        self.deadlinePieces.removeAll()
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
