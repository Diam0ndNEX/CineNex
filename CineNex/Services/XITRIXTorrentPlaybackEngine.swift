import Foundation
import LibTorrent

enum XITRIXTorrentFileSupport {
    static func contentType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "mp4": return "video/mp4"
        case "m4v": return "video/x-m4v"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "avi": return "video/x-msvideo"
        case "webm": return "video/webm"
        case "ts", "m2ts", "mts": return "video/mp2t"
        case "flv": return "video/x-flv"
        case "wmv": return "video/x-ms-wmv"
        case "ogv": return "video/ogg"
        case "mpg", "mpeg", "mpe": return "video/mpeg"
        case "3gp", "3g2": return "video/3gpp"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
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
        tailBytes: Int64 = 1 * 1_024 * 1_024,
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
    private let onPreparationUpdate: @Sendable (String) -> Void
    private var session: Session?
    private var handle: TorrentHandle?
    private var downloadRoot: URL?
    private var reader: TorrentDiskByteReader?
    private var preparedFile: TorrentPreparedFile?
    private var prioritizedPieces = Set<Int64>()
    private var startupPiecePriorities: [Int64: Int] = [:]
    private var activePieceLength: Int64 = 0
    private var deadlinePieces = Set<Int64>()
    private var lifecycleGeneration: UInt64 = 0
    private var isStopping = false
    private var lastSnapshotRefresh = -Double.infinity
    private let monitorOwner = UUID()
    private var monitorTask: Task<Void, Never>?
    private var monitorStarted = ProcessInfo.processInfo.systemUptime
    private var lastTelemetryUpdate = -Double.infinity
    private var lastFailure: String?
    private var pendingPieceRequests: [UUID: Set<Int64>] = [:]
    private var waitingBufferPieces: Set<Int64> { pendingPieceRequests.values.reduce(into: Set<Int64>()) { $0.formUnion($1) } }
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    init(descriptor: StremioTorrentDescriptor, onPreparationUpdate: @escaping @Sendable (String) -> Void = { _ in }) {
        self.descriptor = descriptor
        self.onPreparationUpdate = onPreparationUpdate
    }

    func prepareFiles(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile] {
        await waitForStopCompletion()
        guard request.isValid else { throw TorrentStreamingError.invalidRequest }
        if let preparedFile { return [preparedFile] }

        let generation = lifecycleGeneration
        monitorStarted = ProcessInfo.processInfo.systemUptime
        lastFailure = nil
        await TorrentPlaybackMonitor.shared.begin(owner: monitorOwner)
        do {
            let files = try await prepareFilesInternal(for: request, generation: generation)
            try ensureCurrentLifecycle(generation)
            return files
        } catch {
            PlaybackDiagnostics.record("torrent.prepare.error", details: ["domain": (error as NSError).domain, "code": String((error as NSError).code), "reason": error.localizedDescription])
            if lifecycleGeneration == generation {
                lastFailure = error is CancellationError ? nil : error.localizedDescription
                await stop()
            }
            throw error
        }
    }

    private func prepareFilesInternal(
        for request: PlaybackSourceRequest,
        generation: UInt64
    ) async throws -> [TorrentPreparedFile] {
        try ensureCurrentLifecycle(generation)

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
        self.downloadRoot = root
        await TorrentCacheMaintenance.shared.register(root)
        await TorrentCacheMaintenance.shared.trim()
        try ensureCurrentLifecycle(generation)
        let torrentsDirectory = root.appendingPathComponent("metadata", isDirectory: true)
        let resumeDirectory = root.appendingPathComponent("resume", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: torrentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resumeDirectory, withIntermediateDirectories: true)

        let settings = Session.Settings()
        settings.agentName = "CineNex"
        let profile = TorrentTransferProfile(rawValue: UserDefaults.standard.string(forKey: "cinenex.transferProfile") ?? "balanced") ?? .balanced
        settings.maxDownloadSpeed = numericCast(profile.downloadBytesPerSecond)
        settings.maxUploadSpeed = numericCast(profile.uploadBytesPerSecond)
        settings.outgoingInterfaces = ""
        settings.listenInterfaces = "0.0.0.0:0,[::]:0"
        settings.maxActiveTorrents = 1
        settings.maxDownloadingTorrents = 1
        settings.maxUploadingTorrents = 1
        settings.isDhtEnabled = true
        settings.isLsdEnabled = false
        settings.isUtpEnabled = false
        settings.isUpnpEnabled = false
        settings.isNatEnabled = false
        settings.preallocateStorage = false
        settings.validateHttpsTrackers = true

        onPreparationUpdate("Starting torrent engine…")
        PlaybackDiagnostics.record("Creating libtorrent session")
        guard let session = Session(
            root,
            torrentsPath: torrentsDirectory,
            fastResumePath: resumeDirectory,
            settings: settings,
            storages: [:]
        ) else {
            let message = UserDefaults.standard.string(forKey: "cinenex.nativeSessionInitializationError")
                ?? "Native torrent session could not be initialized."
            PlaybackDiagnostics.record("Native session initialization failed", details: ["reason": message])
            throw NSError(domain: "CineNex.NativeSession", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        PlaybackDiagnostics.record("Libtorrent session created")
        self.downloadRoot = root
        self.session = session

        guard let bootstrapped = SceneBoxTorrentBootstrap.withDefaultTrackers(descriptor),
              let magnet = MagnetURI(with: bootstrapped.magnetURL) else {
            throw TorrentStreamingError.invalidRequest
        }
        PlaybackDiagnostics.record("Adding magnet to libtorrent", details: ["tracker_count": String(bootstrapped.trackers.count), "transport": "tcp", "bootstrap_profile": "scenebox"] )
        guard let handle = session.addTorrent(magnet) else {
            throw TorrentStreamingError.engineUnavailable
        }

        self.handle = handle
        session.resume()
        handle.resume()

        PlaybackDiagnostics.record("Waiting for torrent metadata")
        let snapshot = try await waitForMetadata(on: handle, generation: generation)
        try ensureCurrentLifecycle(generation)
        onPreparationUpdate("Metadata received. Selecting the video…")
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
        handle.setFilePriority(FileEntry.Priority.dontDownload, at: selectedFileIndex)

        refreshSnapshot(handle)
        guard let pieceStates = handle.snapshot.pieces,
              let startupPlan = TorrentStartupPiecePriorityPlan.make(
                fileStartOffset: Int64(selectedFile.fileOffset),
                fileLength: Int64(selectedFile.size),
                pieceLength: Int64(snapshot.pieceLength),
                pieceCount: Int64(pieceStates.count),
                headBytes: TorrentPlaybackTuning.strategy(UserDefaults.standard.string(forKey: "cinenex.bufferStrategy")).openingBytes
              ) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        for (piece, priority) in startupPlan.priorities.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            guard handle.setPiecePriority(priority, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
        activePieceLength = Int64(snapshot.pieceLength)
        startupPiecePriorities = startupPlan.priorities
        // A sparse file existing is not evidence this release can start. Verify actual startup
        // pieces before advertising the loopback URL, so automatic selection can reject dead swarms.
        let startupPieces = Set(startupPlan.priorities.keys)
        for piece in startupPieces.sorted() {
            guard handle.setPieceDeadline(0, at: Int(piece)) else {
                throw TorrentStreamingError.invalidTorrentLayout
            }
        }
        deadlinePieces = startupPieces
        try await waitForStartupBuffer(pieces: startupPieces, on: handle, generation: generation)

        try await waitForFile(at: fileURL, expectedLength: Int64(selectedFile.size), generation: generation)
        try ensureCurrentLifecycle(generation)
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
        PlaybackDiagnostics.record("torrent.file.prepared", details: ["file_index": String(selectedFile.index), "bytes": String(selectedFile.size), "piece_length": String(snapshot.pieceLength), "content_type": contentType])
        self.reader = reader
        self.preparedFile = prepared
        await publishTelemetry(handle.snapshot, stage: .ready, detail: "Opening buffer verified. Starting the player…", required: Set(startupPiecePriorities.keys), force: true)
        try ensureCurrentLifecycle(generation)
        startTelemetryMonitoring(generation: generation)
        return [prepared]
    }

    func prioritize(pieces: Range<Int64>) async throws {
        try Task.checkCancellation()
        guard let handle else { throw TorrentStreamingError.engineUnavailable }
        guard !pieces.isEmpty else { return }

        refreshSnapshot(handle)
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
                pieceCount: pieceCount,
                lookBehind: min(2, (2 * 1_024 * 1_024) / max(1, activePieceLength)),
                lookAhead: min(24, max(1, (8 * 1_024 * 1_024) / max(1, activePieceLength)))
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

        if requestedPieces == prioritizedPieces, requestedDeadlinePieces == deadlinePieces { return }
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
            let fallbackPriority = startupPiecePriorities[piece] ?? 0
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
        let generation = lifecycleGeneration
        try ensureCurrentLifecycle(generation)
        guard let handle else { throw TorrentStreamingError.engineUnavailable }
        guard !pieces.isEmpty else { return }
        refreshSnapshot(handle)
        guard let initialPieceStates = handle.snapshot.pieces,
              pieces.allSatisfy({ $0 >= 0 && $0 < Int64(initialPieceStates.count) }) else {
            throw TorrentStreamingError.invalidTorrentLayout
        }
        let readID = UUID()
        defer { pendingPieceRequests.removeValue(forKey: readID) }
        let started = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - started < 30 {
            try Task.checkCancellation()
            try ensureCurrentLifecycle(generation)
            refreshSnapshot(handle)
            let availablePieces = handle.snapshot.pieces ?? []
            if pieces.allSatisfy({ index in
                index >= 0 &&
                index < Int64(availablePieces.count) &&
                availablePieces[Int(index)].boolValue
            }) {
                if pendingPieceRequests.removeValue(forKey: readID) != nil {
                    let remaining = waitingBufferPieces
                    await publishTelemetry(handle.snapshot, stage: remaining.isEmpty ? .ready : .buffering,
                                           detail: remaining.isEmpty ? "Requested video data is ready." : "Downloading video ranges requested by the player.",
                                           required: remaining.isEmpty ? Set(pieces) : remaining, force: true)
                }
                return
            }
            pendingPieceRequests[readID] = Set(pieces)
            await publishTelemetry(handle.snapshot, stage: .buffering, detail: "Downloading video ranges requested by the player.", required: waitingBufferPieces)
            PlaybackDiagnostics.sample("torrent.pieces.wait", details: [
                "from": String(pieces.lowerBound), "to_exclusive": String(pieces.upperBound),
                "wait_seconds": String(Int(ProcessInfo.processInfo.systemUptime - started)), "download_bytes_per_second": String(handle.snapshot.downloadRate),
                "peers": String(handle.snapshot.numberOfPeers), "seeds": String(handle.snapshot.numberOfSeeds)
            ])
            try await Task.sleep(for: .milliseconds(250))
        }
        PlaybackDiagnostics.record("torrent.pieces.timeout")
        throw TorrentStreamingError.pieceAvailabilityTimeout
    }

    private func waitForStartupBuffer(pieces: Set<Int64>, on handle: TorrentHandle, generation: UInt64) async throws {
        guard !pieces.isEmpty else { throw TorrentStreamingError.invalidTorrentLayout }
        let started = ProcessInfo.processInfo.systemUptime
        onPreparationUpdate("Downloading the opening buffer…")
        while ProcessInfo.processInfo.systemUptime - started < 20 {
            try ensureCurrentLifecycle(generation)
            refreshSnapshot(handle)
            let snapshot = handle.snapshot
            guard ProcessInfo.processInfo.systemUptime - started < 20 else { break }
            let states = (snapshot.pieces ?? []).map(\.boolValue)
            let counts = TorrentStartupReadiness.counts(required: pieces, available: states)
            await publishTelemetry(snapshot, stage: .initialBuffer,
                                   detail: "Verifying the opening and container index pieces before playback.", required: pieces)
            if counts.ready == counts.total {
                PlaybackDiagnostics.record("torrent.startup.ready", details: ["pieces": String(counts.total), "elapsed_seconds": String(ProcessInfo.processInfo.systemUptime - started)])
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        PlaybackDiagnostics.record("torrent.startup.timeout", details: ["required_pieces": String(pieces.count)])
        throw TorrentStreamingError.pieceAvailabilityTimeout
    }

    private func publishTelemetry(_ snapshot: TorrentHandle.Snapshot, stage: TorrentPlaybackSnapshot.Stage,
                                  detail: String, required: Set<Int64> = [], force: Bool = false) async {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastTelemetryUpdate >= 0.75 else { return }
        lastTelemetryUpdate = now
        let counts = TorrentStartupReadiness.counts(required: required, available: (snapshot.pieces ?? []).map(\.boolValue))
        let value = TorrentPlaybackSnapshot(stage: stage, detail: detail,
            downloadBytesPerSecond: snapshot.downloadRate, downloadedBytes: snapshot.totalDownload,
            peers: Int(clamping: snapshot.numberOfPeers), seeds: Int(clamping: snapshot.numberOfSeeds),
            availablePieces: counts.ready, requiredPieces: counts.total,
            elapsedSeconds: max(0, Int(now - monitorStarted)), sampleDate: Date())
        await TorrentPlaybackMonitor.shared.publish(value, owner: monitorOwner)
    }

    private func startTelemetryMonitoring(generation: UInt64) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                guard await self.samplePlaybackTelemetry(generation: generation) else { return }
            }
        }
    }

    private func samplePlaybackTelemetry(generation: UInt64) async -> Bool {
        guard lifecycleGeneration == generation, !isStopping, let handle else { return false }
        refreshSnapshot(handle)
        let isWaiting = !waitingBufferPieces.isEmpty
        await publishTelemetry(handle.snapshot, stage: isWaiting ? .buffering : .ready,
                               detail: isWaiting ? "Downloading the video range requested by the player." : "Streaming verified torrent data to the player.",
                               required: waitingBufferPieces)
        return lifecycleGeneration == generation && !isStopping
    }

    private var retainPartialTransfers: Bool {
        UserDefaults.standard.object(forKey: "cinenex.retainPartialTransfers") as? Bool ?? true
    }

    func stop() async {
        if isStopping {
            await waitForStopCompletion()
            return
        }
        isStopping = true
        lifecycleGeneration &+= 1
        monitorTask?.cancel()
        monitorTask = nil
        await TorrentPlaybackMonitor.shared.finish(owner: monitorOwner, error: lastFailure)
        defer {
            isStopping = false
            let waiters = stopWaiters
            stopWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        if let reader {
            try? await reader.close()
        }
        if let handle, let session {
            handle.pause()
            session.removeTorrent(handle, deleteFiles: false)
        }
        session?.shutdown()
        if let downloadRoot {
            if retainPartialTransfers {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: downloadRoot.path)
            }
            await TorrentCacheMaintenance.shared.release(downloadRoot, removeIfUnused: !retainPartialTransfers)
            await TorrentCacheMaintenance.shared.trim()
        }
        self.reader = nil
        self.preparedFile = nil
        self.prioritizedPieces.removeAll()
        self.startupPiecePriorities.removeAll()
        self.activePieceLength = 0
        self.deadlinePieces.removeAll()
        self.pendingPieceRequests.removeAll()
        self.handle = nil
        lastSnapshotRefresh = -Double.infinity
        self.session = nil
        self.downloadRoot = nil
    }

    /// VLC makes many small byte reads. Reuse one snapshot per polling interval.
    private func refreshSnapshot(_ handle: TorrentHandle) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSnapshotRefresh >= 0.5 else { return }
        handle.updateSnapshot()
        lastSnapshotRefresh = ProcessInfo.processInfo.systemUptime
    }

    private func waitForStopCompletion() async {
        guard isStopping else { return }
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }

    private func ensureCurrentLifecycle(_ expectedGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard lifecycleGeneration == expectedGeneration else {
            throw CancellationError()
        }
    }

    private func waitForMetadata(
        on handle: TorrentHandle,
        generation: UInt64
    ) async throws -> TorrentHandle.Snapshot {
        let started = ProcessInfo.processInfo.systemUptime
        var lastUpdate = -Double.infinity
        while ProcessInfo.processInfo.systemUptime - started < 20 {
            try ensureCurrentLifecycle(generation)
            let snapshotStarted = ProcessInfo.processInfo.systemUptime
            PlaybackDiagnostics.sample("torrent.metadata.snapshot.begin", details: [:])
            refreshSnapshot(handle)
            let snapshot = handle.snapshot
            let now = ProcessInfo.processInfo.systemUptime
            guard now - started < 20 else { break }
            let snapshotDuration = now - snapshotStarted
            if snapshotDuration > 1 {
                PlaybackDiagnostics.record("torrent.metadata.snapshot.slow", details: ["seconds": String(format: "%.3f", snapshotDuration)])
            }
            await publishTelemetry(snapshot, stage: snapshot.numberOfPeers == 0 ? .findingPeers : .metadata,
                                   detail: snapshot.numberOfPeers == 0 ? "Contacting trackers and discovering peers." : "Peers connected. Receiving the torrent file list.")
            if now - lastUpdate >= 2 {
                lastUpdate = now
                let peers = snapshot.numberOfPeers
                onPreparationUpdate(peers == 0
                    ? "Finding peers… No connections yet. Try another release if this stays here."
                    : "Connected to \(peers) peers. Fetching video metadata…")
                PlaybackDiagnostics.sample("torrent.metadata.wait", details: [
                    "wait_seconds": String(Int(now - started)), "has_metadata": String(snapshot.hasMetadata),
                    "files": String(snapshot.files.count), "peers": String(snapshot.numberOfPeers),
                    "configured_trackers": String(SceneBoxTorrentBootstrap.withDefaultTrackers(descriptor)?.trackers.count ?? descriptor.trackers.count),
                    "seeds": String(snapshot.numberOfSeeds), "download_bytes_per_second": String(snapshot.downloadRate)
                ])
            }
            if snapshot.hasMetadata, !snapshot.files.isEmpty {
                return snapshot
            }
            try await Task.sleep(for: .seconds(1))
        }
        PlaybackDiagnostics.record("torrent.metadata.timeout")
        throw TorrentStreamingError.metadataTimeout
    }

    private func waitForFile(
        at url: URL,
        expectedLength: Int64,
        generation: UInt64
    ) async throws {
        for _ in 0..<20 {
            try ensureCurrentLifecycle(generation)
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
