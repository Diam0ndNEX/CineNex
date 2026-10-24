import SwiftUI

struct OfflineLibraryView: View {
    @StateObject private var store = OfflineDownloadStore.shared
    @State private var retryErrorMessage: String?
    @State private var showingRetryError = false
    let onPlay: (OfflineDownload, URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloads")
                        .font(.largeTitle.bold())
                    Text("Manage media saved on this device.")
                        .foregroundStyle(.secondary)
                }

                if store.downloads.isEmpty {
                    ContentUnavailableView(
                        "No offline downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("When you download a supported HLS source from a title page, it will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 45)
                } else {
                    ForEach(store.downloads) { download in
                        OfflineDownloadRow(
                            download: download,
                            localURL: store.localPlaybackURL(for: download.id),
                            onPlay: { url in onPlay(download, url) },
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
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refreshStoredState() }
        .alert("Could Not Retry Download", isPresented: $showingRetryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(retryErrorMessage ?? "The download could not be restarted.")
        }
    }
}

private struct OfflineDownloadRow: View {
    let download: OfflineDownload
    let localURL: URL?
    let onPlay: (URL) -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    private var statusText: String {
        switch download.status {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .completed: return "Downloaded"
        case .failed: return "Download failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusSymbol: String {
        switch download.status {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle"
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
                    Label(statusText, systemImage: statusSymbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(download.status == .failed ? .orange : .secondary)
                    if download.status == .downloading || download.status == .queued {
                        ProgressView(value: download.progress)
                            .tint(Color.cineNexAccent)
                        Text(download.status == .queued ? "Waiting to start" : "\(Int(download.progress * 100))%")
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

                if download.status == .queued || download.status == .downloading {
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
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}
