import SwiftUI

enum OfflineDownloadFilter: String, CaseIterable, Identifiable {
    case all
    case saved
    case active
    case issues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .saved: return "Saved"
        case .active: return "Active"
        case .issues: return "Issues"
        }
    }

    func includes(_ download: OfflineDownload) -> Bool {
        switch self {
        case .all:
            return true
        case .saved:
            return download.status == .completed
        case .active:
            return download.status == .queued || download.status == .downloading || download.status == .paused
        case .issues:
            return download.status == .failed || download.status == .cancelled
        }
    }
}

struct OfflineLibraryView: View {
    @StateObject private var store = OfflineDownloadStore.shared
    @State private var searchText = ""
    @State private var selectedFilter: OfflineDownloadFilter = .all
    @State private var retryErrorMessage: String?
    @State private var showingRetryError = false
    @State private var showingRemoveCompletedConfirmation = false
    let onPlay: (OfflineDownload, URL) -> Void

    private var filteredDownloads: [OfflineDownload] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.downloads.filter { download in
            selectedFilter.includes(download) &&
                (query.isEmpty ||
                 download.title.localizedCaseInsensitiveContains(query) ||
                 (download.errorMessage?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    private var activeDownloadCount: Int {
        store.downloads.filter { OfflineDownloadFilter.active.includes($0) }.count
    }

    private var issueDownloadCount: Int {
        store.downloads.filter { OfflineDownloadFilter.issues.includes($0) }.count
    }

    private var savedDownloadCount: Int {
        store.downloads.filter { OfflineDownloadFilter.saved.includes($0) }.count
    }

    private var completedDownloadCount: Int {
        store.downloads.filter { download in
            download.status == .completed && store.localPlaybackURL(for: download.id) != nil
        }.count
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("ON THIS DEVICE", systemImage: "internaldrive")
                    .font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Color.cineNexAccent)
                Spacer()
                Menu {
                    Button("Pause active transfers", systemImage: "pause") {
                        for download in store.downloads where download.status == .downloading { store.pause(id: download.id) }
                    }
                    Button("Resume paused transfers", systemImage: "play") {
                        for download in store.downloads where download.status == .paused { store.resume(id: download.id) }
                    }
                    if completedDownloadCount > 0 {
                        Button("Remove completed downloads", systemImage: "trash", role: .destructive) {
                            showingRemoveCompletedConfirmation = true
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .accessibilityLabel("Download management")
            }
            Text(ByteCountFormatter.string(fromByteCount: store.storageUsageBytes, countStyle: .file))
                .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
            Text("Media stored locally").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                summaryButton("Ready", count: savedDownloadCount, filter: .saved)
                summaryButton("Transfers", count: activeDownloadCount, filter: .active)
                summaryButton("Attention", count: issueDownloadCount, filter: .issues)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 26))
    }

    private func summaryButton(_ title: String, count: Int, filter: OfflineDownloadFilter) -> some View {
        Button { selectedFilter = filter } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(count)).font(.title2.bold()).foregroundStyle(.primary)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Color.cineNexBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
        .accessibilityLabel("\(count) \(title) downloads")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR OFFLINE CINEMA").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.cineNexAccent)
                    Text("Ready when you are.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Manage transfers and keep your next watch close.")
                        .foregroundStyle(.secondary)
                }

                storageSummary

                if store.downloads.isEmpty {
                    ContentUnavailableView(
                        "No offline downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("When you download a supported HLS source from a title page, it will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 45)
                } else {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search downloads", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Search offline downloads")
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear download search")
                            }
                        }
                        .padding(12)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 12))

                        Picker("Filter downloads", selection: $selectedFilter) {
                            Text("All").tag(OfflineDownloadFilter.all)
                            Text("Saved").tag(OfflineDownloadFilter.saved)
                            Text("Active").tag(OfflineDownloadFilter.active)
                            Text("Issues").tag(OfflineDownloadFilter.issues)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Filter offline downloads")

                        HStack {
                            Text("\(filteredDownloads.count) of \(store.downloads.count) downloads")
                            Spacer()
                            if selectedFilter != .all || !searchText.isEmpty {
                                Button("Reset filters") {
                                    selectedFilter = .all
                                    searchText = ""
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if filteredDownloads.isEmpty {
                        ContentUnavailableView(
                            "No matching downloads",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Try another search or filter to find your downloads.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        ForEach(filteredDownloads) { download in
                            OfflineDownloadRow(
                                download: download,
                                localURL: store.localPlaybackURL(for: download.id),
                                onPlay: { url in onPlay(download, url) },
                                onPause: { store.pause(id: download.id) },
                                onResume: { store.resume(id: download.id) },
                                onCancel: { store.cancel(id: download.id) },
                                onRemove: { store.remove(id: download.id) },
                                onRetry: {
                                    do {
                                        try store.enqueue(title: download.title, sourceURL: download.sourceURL)
                                    } catch {
                                        retryErrorMessage = error.localizedDescription
                                        showingRetryError = true
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Offline")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refreshStoredState() }
        .alert("Could Not Retry Download", isPresented: $showingRetryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(retryErrorMessage ?? "The download could not be restarted.")
        }
        .confirmationDialog(
            "Remove all completed downloads?",
            isPresented: $showingRemoveCompletedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove \(completedDownloadCount) Downloads", role: .destructive) {
                store.removeCompletedDownloads()
            }
        } message: {
            Text("This permanently deletes downloaded media from this device. Active downloads are not affected.")
        }
    }
}

private struct OfflineDownloadRow: View {
    let download: OfflineDownload
    let localURL: URL?
    let onPlay: (URL) -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    private var statusText: String {
        switch download.status {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Downloaded"
        case .failed: return "Download failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusSymbol: String {
        switch download.status {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 46, height: 62)
                    .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 5) {
                    Text(download.title)
                        .font(.headline)
                        .lineLimit(2)
                    Label(statusText.uppercased(), systemImage: statusSymbol)
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(download.status == .failed ? .orange : .secondary)
                    if download.status == .downloading || download.status == .queued || download.status == .paused {
                        ProgressView(value: download.progress)
                            .tint(Color.cineNexAccent)
                        Text(download.status == .queued ? "Waiting to start" : download.status == .paused ? "Paused at \(Int(download.progress * 100))%" : "\(Int(download.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let error = download.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if download.status == .completed, let localURL {
                    Button {
                        onPlay(localURL)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if download.status == .downloading {
                    Button(action: onPause) {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if download.status == .paused || download.status == .queued {
                    Button(action: onResume) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if download.status == .queued || download.status == .downloading || download.status == .paused {
                    Button(action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if download.status == .failed || download.status == .cancelled {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.05)) }
    }
}
