import AVFoundation
import Combine
import Foundation

enum OfflineDownloadStatus: String, Codable, Equatable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

struct OfflineDownload: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let sourceURL: URL
    let createdAt: Date
    var updatedAt: Date
    var status: OfflineDownloadStatus
    var progress: Double
    var localDirectoryName: String?
    var errorMessage: String?

    func localDirectoryURL(in downloadsDirectory: URL) -> URL? {
        guard let localDirectoryName,
              localDirectoryName == "\(id).movpkg",
              URL(fileURLWithPath: localDirectoryName).lastPathComponent == localDirectoryName else {
            return nil
        }

        let root = downloadsDirectory.standardizedFileURL
        let url = root.appendingPathComponent(localDirectoryName, isDirectory: true).standardizedFileURL
        guard url.deletingLastPathComponent() == root else { return nil }
        return url
    }

    func localAssetURL(in downloadsDirectory: URL) -> URL? {
        guard status == .completed,
              let url = localDirectoryURL(in: downloadsDirectory),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileType = attributes[.type] as? FileAttributeType,
              fileType == .typeDirectory else {
            return nil
        }
        return url
    }
}

enum OfflineDownloadError: LocalizedError {
    case invalidTitle
    case unsupportedSource
    case unableToCreateTask
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidTitle:
            return "Enter a title before downloading."
        case .unsupportedSource:
            return "Offline downloads currently support HTTPS HLS playlists ending in .m3u8. Other formats and protected streams are not supported."
        case .unableToCreateTask:
            return "CineNex could not create a download task for this source."
        case .storageUnavailable:
            return "CineNex could not prepare its offline media folder."
        }
    }
}

@MainActor
final class OfflineDownloadStore: NSObject, ObservableObject, AVAssetDownloadDelegate {
    static let shared = OfflineDownloadStore()

    @Published private(set) var downloads: [OfflineDownload] = []

    private let defaults: UserDefaults
    private let storageKey: String
    private let downloadsDirectory: URL
    private var session: AVAssetDownloadURLSession!
    private var tasks: [String: AVAssetDownloadTask] = [:]

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "cinenex.offlineDownloads",
        downloadsDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let downloadsDirectory {
            self.downloadsDirectory = downloadsDirectory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.downloadsDirectory = applicationSupport
                .appendingPathComponent("CineNex", isDirectory: true)
                .appendingPathComponent("OfflineMedia", isDirectory: true)
        }
        super.init()

        restoreDownloads()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.diam0ndnex.cinenex.offline-downloads"
        )
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue.main
        )
        reconnectTasks()
    }

    nonisolated static func supportsOfflineDownload(from url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.pathExtension.lowercased() == "m3u8"
            && url.host != nil
    }

    var storageUsageBytes: Int64 {
        downloads.reduce(Int64(0)) { total, record in
            guard let localURL = record.localAssetURL(in: downloadsDirectory) else {
                return total
            }
            return total + Self.directorySize(at: localURL)
        }
    }

    @discardableResult
    func enqueue(title: String, sourceURL: URL) throws -> OfflineDownload {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw OfflineDownloadError.invalidTitle
        }
        guard Self.supportsOfflineDownload(from: sourceURL) else {
            throw OfflineDownloadError.unsupportedSource
        }

        if let index = downloads.firstIndex(where: {
            $0.sourceURL == sourceURL && $0.status != .cancelled && $0.status != .failed
        }) {
            let existing = downloads[index]
            if existing.status != .completed {
                return existing
            }
            if existing.localAssetURL(in: downloadsDirectory) != nil {
                return existing
            }

            downloads[index].status = .failed
            downloads[index].errorMessage = "The downloaded media file is missing. Download it again to restore offline playback."
            downloads[index].updatedAt = Date()
            persist()
        }

        try prepareDownloadsDirectory()
        let now = Date()
        let record = OfflineDownload(
            id: UUID().uuidString,
            title: cleanTitle,
            sourceURL: sourceURL,
            createdAt: now,
            updatedAt: now,
            status: .queued,
            progress: 0,
            localDirectoryName: nil,
            errorMessage: nil
        )
        downloads.append(record)
        sortAndPersist()
        startDownload(for: record)
        return record
    }

    func pause(id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .downloading else {
            return
        }

        tasks[id]?.suspend()
        downloads[index].status = .paused
        downloads[index].updatedAt = Date()
        persist()
    }

    func resume(id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .paused || downloads[index].status == .queued else {
            return
        }

        if let task = tasks[id] {
            switch task.state {
            case .suspended:
                task.resume()
                downloads[index].status = .downloading
                downloads[index].updatedAt = Date()
                persist()
                return
            case .running:
                downloads[index].status = .downloading
                downloads[index].updatedAt = Date()
                persist()
                return
            case .canceling, .completed:
                tasks[id] = nil
            @unknown default:
                tasks[id] = nil
            }
        }

        downloads[index].progress = 0
        downloads[index].status = .queued
        downloads[index].updatedAt = Date()
        persist()
        startDownload(for: downloads[index])
    }

    func cancel(id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        downloads[index].status = .cancelled
        downloads[index].errorMessage = nil
        downloads[index].updatedAt = Date()
        persist()
    }

    func remove(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil

        if let record = downloads.first(where: { $0.id == id }),
           let localURL = record.localDirectoryURL(in: downloadsDirectory) {
            try? FileManager.default.removeItem(at: localURL)
        }

        downloads.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func removeCompletedDownloads() -> Int {
        let completedRecords = downloads.filter { $0.status == .completed }
        guard !completedRecords.isEmpty else { return 0 }

        for record in completedRecords {
            tasks[record.id]?.cancel()
            tasks[record.id] = nil
            if let localURL = record.localDirectoryURL(in: downloadsDirectory) {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        let completedIDs = Set(completedRecords.map(\.id))
        downloads.removeAll { completedIDs.contains($0.id) }
        persist()
        return completedRecords.count
    }

    func localPlaybackURL(for id: String) -> URL? {
        guard let record = downloads.first(where: { $0.id == id }) else { return nil }
        return record.localAssetURL(in: downloadsDirectory)
    }

    func refreshStoredState() {
        restoreDownloads()
        reconnectTasks()
    }

    private func startDownload(for record: OfflineDownload) {
        guard let index = downloads.firstIndex(where: { $0.id == record.id }) else { return }
        let asset = AVURLAsset(url: record.sourceURL)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: record.title,
            assetArtworkData: nil,
            options: nil
        ) else {
            downloads[index].status = .failed
            downloads[index].errorMessage = OfflineDownloadError.unableToCreateTask.localizedDescription
            downloads[index].updatedAt = Date()
            persist()
            return
        }

        task.taskDescription = record.id
        tasks[record.id] = task
        downloads[index].status = .downloading
        downloads[index].updatedAt = Date()
        persist()
        task.resume()
    }

    private func reconnectTasks() {
        session.getAllTasks { [weak self] allTasks in
            guard let self else { return }
            Task { @MainActor in
                let activeTasks = allTasks.compactMap { $0 as? AVAssetDownloadTask }
                let activeIDs = Set(activeTasks.compactMap(\.taskDescription))
                for task in activeTasks {
                    guard let id = task.taskDescription else { continue }
                    self.tasks[id] = task
                    guard let index = self.downloads.firstIndex(where: { $0.id == id }) else { continue }
                    switch task.state {
                    case .suspended:
                        self.downloads[index].status = .paused
                    case .running:
                        self.downloads[index].status = .downloading
                    case .canceling:
                        self.downloads[index].status = .cancelled
                    case .completed:
                        break
                    @unknown default:
                        break
                    }
                }

                for index in self.downloads.indices where self.downloads[index].status == .downloading {
                    let id = self.downloads[index].id
                    guard !activeIDs.contains(id) else { continue }
                    if let task = self.tasks[id] {
                        switch task.state {
                        case .running:
                            continue
                        case .suspended:
                            self.downloads[index].status = .paused
                            continue
                        case .canceling, .completed:
                            self.tasks[id] = nil
                        @unknown default:
                            self.tasks[id] = nil
                        }
                    }
                    self.downloads[index].status = .queued
                }
                self.persist()

                let queued = self.downloads.filter { $0.status == .queued }
                for record in queued {
                    self.startDownload(for: record)
                }
            }
        }
    }

    nonisolated static func directorySize(at directoryURL: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: []
              ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0 else {
                continue
            }
            totalBytes += Int64(fileSize)
        }
        return totalBytes
    }

    private func prepareDownloadsDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: downloadsDirectory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var directory = downloadsDirectory
            try directory.setResourceValues(values)
        } catch {
            throw OfflineDownloadError.storageUnavailable
        }
    }

    private func restoreDownloads() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([OfflineDownload].self, from: data) else {
            downloads = []
            return
        }
        var restored = decoded.filter { record in
            !record.id.isEmpty
                && !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.supportsOfflineDownload(from: record.sourceURL)
                && record.progress.isFinite
                && (0...1).contains(record.progress)
        }

        for index in restored.indices where restored[index].status == .completed {
            guard restored[index].localAssetURL(in: downloadsDirectory) == nil else { continue }
            restored[index].status = .failed
            restored[index].errorMessage = "The downloaded media file is missing. Download it again to restore offline playback."
            restored[index].updatedAt = Date()
        }

        downloads = restored
        sortAndPersist()
    }

    private func sortAndPersist() {
        downloads.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func updateRecord(id: String, _ update: (inout OfflineDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        update(&downloads[index])
        downloads[index].updatedAt = Date()
        persist()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad expectedTimeRange: CMTimeRange
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let loadedSeconds = loadedTimeRanges.reduce(0.0) { total, value in
            let duration = CMTimeGetSeconds(value.timeRangeValue.duration)
            return total + (duration.isFinite && duration > 0 ? duration : 0)
        }
        let expectedSeconds = CMTimeGetSeconds(expectedTimeRange.duration)
        guard expectedSeconds.isFinite, expectedSeconds > 0 else { return }
        let progress = min(max(loadedSeconds / expectedSeconds, 0), 0.99)
        Task { @MainActor [weak self] in
            self?.updateRecord(id: id) { record in
                guard record.status == .downloading else { return }
                record.progress = progress
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.finishDownload(id: id, location: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        Task { @MainActor [weak self] in
            self?.completeDownload(id: id, error: error)
        }
    }

    private func finishDownload(id: String, location: URL) {
        guard downloads.contains(where: { $0.id == id }) else { return }

        do {
            try prepareDownloadsDirectory()
            let destination = downloadsDirectory.appendingPathComponent("\(id).movpkg", isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            updateRecord(id: id) { record in
                record.status = .completed
                record.progress = 1
                record.localDirectoryName = destination.lastPathComponent
                record.errorMessage = nil
            }
            tasks[id] = nil
        } catch {
            updateRecord(id: id) { record in
                record.status = .failed
                record.errorMessage = "The downloaded media could not be saved locally: \(error.localizedDescription)"
            }
            tasks[id] = nil
        }
    }

    private func completeDownload(id: String, error: Error) {
        if (error as NSError).code == NSURLErrorCancelled {
            updateRecord(id: id) { record in
                if record.status != .cancelled {
                    record.status = .cancelled
                }
            }
        } else {
            updateRecord(id: id) { record in
                guard record.status != .completed else { return }
                record.status = .failed
                record.errorMessage = error.localizedDescription
            }
        }
        tasks[id] = nil
    }
}
