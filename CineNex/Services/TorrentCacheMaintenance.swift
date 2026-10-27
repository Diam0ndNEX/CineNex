import Foundation

/// A bounded cache of partial transfers, not an offline-download library.
actor TorrentCacheMaintenance {
    static let shared = TorrentCacheMaintenance()
    private var active: [URL: Int] = [:]
    private let budget: Int64
    private let directory: URL?
    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("CineNex/Torrents"), budget: Int64 = 2 * 1_024 * 1_024 * 1_024) {
        self.directory = directory
        self.budget = max(0, budget)
    }
    func register(_ root: URL) { active[root.standardizedFileURL, default: 0] += 1 }
    func release(_ root: URL, removeIfUnused: Bool = false) {
        let url = root.standardizedFileURL
        if let count = active[url], count > 1 { active[url] = count - 1 }
        else {
            active[url] = nil
            if removeIfUnused { try? FileManager.default.removeItem(at: url) }
        }
    }

    func trim(clear: Bool = false) {
        guard let directory,
              let roots = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { return }
        let entries = roots.compactMap { root -> (URL, Int64, Date)? in
            guard root.lastPathComponent.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
                  let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            var bytes: Int64 = 0
            if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileAllocatedSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                for case let file as URL in files {
                    guard let size = try? file.resourceValues(forKeys: [.fileAllocatedSizeKey, .isSymbolicLinkKey]), size.isSymbolicLink != true else { continue }
                    bytes += Int64(size.fileAllocatedSize ?? 0)
                }
            }
            return (root, bytes, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        for (root, bytes, date) in entries where active[root.standardizedFileURL] == nil {
            if clear || total > budget || Date().timeIntervalSince(date) > 7 * 24 * 3_600 {
                do { try FileManager.default.removeItem(at: root); total -= bytes } catch { }
            }
        }
    }
}
