import SwiftUI

struct CineNexSettingsView: View {
    var onOpenDownloads: (() -> Void)? = nil
    @AppStorage("cinenex.retainPartialTransfers") private var retainPartialTransfers = true
    @State private var showingAppearance = false
    @State private var showingClearConfirmation = false
    @State private var maintenanceMessage: String?
    @AppStorage("cinenex.preferredSubtitleLanguage") private var subtitleLanguage = SubtitleLanguage.deviceDefault.code
    @AppStorage("cinenex.skipSeconds") private var skipSeconds = 10
    @AppStorage("cinenex.defaultPlaybackSpeed") private var playbackSpeed = 1.0
    @AppStorage("cinenex.resumePlayback") private var resumePlayback = true
    @AppStorage("cinenex.transferProfile") private var transferProfile = "balanced"
    @AppStorage("cinenex.canvasStyle") private var canvasStyle = "midnight"
    @AppStorage("cinenex.accentPreset") private var accent = "amber"
    @AppStorage("cinenex.smartPlaybackAttempts") private var smartAttempts = 3
    @AppStorage("cinenex.smartPreferredQuality") private var smartQuality = "1080p"
    @AppStorage("cinenex.smartMaximumSizeGB") private var maximumSizeGB = 0.0
    @AppStorage("cinenex.hideKnownDeadReleases") private var hideKnownDead = false
    @AppStorage("cinenex.bufferStrategy") private var bufferStrategy = "balanced"
    @AppStorage("cinenex.playerControlsDelay") private var controlsDelay = 5
    @AppStorage("cinenex.showTransferHUD") private var showTransferHUD = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PERSONALIZE YOUR EXPERIENCE").font(.system(size: 9, weight: .black)).tracking(2.5).foregroundStyle(Color.cineNexAccent)
                    Text("Settings").font(.system(size: 38, weight: .black, design: .serif))
                    Text("Your layout. Your playback. Your rules.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 20)
                CineNexPreferenceCard(title: "Appearance & layout", symbol: "paintpalette.fill") {
                    Button { showingAppearance = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Customize CineNex").font(.headline)
                                Text("Home shelves, navigation, posters, colors & motion").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle().fill(Color.cineNexAccent).frame(width: 30, height: 30)
                            Image(systemName: "arrow.up.right")
                        }.foregroundStyle(.primary)
                    }.buttonStyle(.plain)
                }
                CineNexPreferenceCard(title: "Playback", symbol: "play.rectangle.fill") {
                    Toggle("Resume movies where I stopped", isOn: $resumePlayback)
                    Divider()
                    Picker("Skip interval", selection: $skipSeconds) {
                        ForEach([10, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Picker("Starting speed", selection: $playbackSpeed) {
                        ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { Text(String(format: "%.2g×", $0)).tag($0) }
                    }
                    Picker("Subtitle language", selection: $subtitleLanguage) {
                        ForEach(SubtitleLanguage.offered) { Text($0.name).tag($0.code) }
                    }
                    Divider()
                    Picker("Opening buffer", selection: $bufferStrategy) {
                        ForEach(TorrentPlaybackTuning.BufferStrategy.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("Quick starts with a smaller buffer. Resilient prepares more video data and uses a longer player cache for less reliable connections.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Hide controls after", selection: $controlsDelay) {
                        ForEach([3, 5, 8], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Toggle("Show transfer details in player", isOn: $showTransferHUD)
                    Text("Preferences apply to newly opened VLC players. Sleep timers are available from the clock in the player.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CineNexPreferenceCard(title: "Automatic source selection", symbol: "play.circle") {
                    Picker("Preferred quality", selection: $smartQuality) {
                        Text("4K · 2160p").tag("2160p")
                        Text("Full HD · 1080p").tag("1080p")
                        Text("HD · 720p").tag("720p")
                    }
                    Picker("Known file size limit", selection: $maximumSizeGB) {
                        Text("No limit").tag(0.0)
                        ForEach([2.0, 5, 10, 20, 40], id: \.self) { Text("Up to \(Int($0)) GB").tag($0) }
                    }
                    Stepper("Try up to \(smartAttempts) releases", value: $smartAttempts, in: 1...5)
                    Toggle("Hide releases reporting zero seeders", isOn: $hideKnownDead)
                    Text("Automatic playback tries actual preparation, then moves on when a release fails. Reported seed counts and sizes can be missing or outdated; unknown metadata is not a health check.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CineNexPreferenceCard(title: "Streaming & storage", symbol: "antenna.radiowaves.left.and.right") {
                    NavigationLink { CineNexProviderSettingsView() } label: {
                        settingsLink("Sources & providers", detail: "Torrentio · MediaFusion · custom add-ons", symbol: "network")
                    }
                    Divider()
                    Picker("Transfer profile", selection: $transferProfile) {
                        ForEach(TorrentTransferProfile.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text((TorrentTransferProfile(rawValue: transferProfile) ?? .balanced).detail)
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Reuse partial torrent data", isOn: $retainPartialTransfers)
                    Text("Inactive partial transfers use up to 2 GiB and expire after 7 days. Active transfers are protected and can exceed that budget. This is a cache, not an offline download.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Applies to the next torrent session. Actual battery use depends on the release, codec and connection.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let onOpenDownloads {
                    CineNexPreferenceCard(title: "Downloads", symbol: "arrow.down.circle") {
                        Button(action: onOpenDownloads) {
                            settingsLink("Offline library", detail: "Download status, storage and saved media", symbol: "internaldrive")
                        }.buttonStyle(.plain)
                    }
                }
                CineNexPreferenceCard(title: "Accounts & tracking", symbol: "person.crop.circle") {
                    NavigationLink { TrackingView() } label: {
                        settingsLink("Accounts & tracking", detail: "Trakt, watch history and imports", symbol: "arrow.triangle.2.circlepath")
                    }
                }
                CineNexPreferenceCard(title: "Diagnostics & maintenance", symbol: "heart.text.square") {
                    NavigationLink { PlaybackDiagnosticsView() } label: {
                        settingsLink("Playback report", detail: "Provider responses, timing and native events", symbol: "waveform.path.ecg")
                    }
                    Divider()
                    Button("Clear inactive partial transfers", systemImage: "internaldrive") {
                        Task { await TorrentCacheMaintenance.shared.trim(clear: true); maintenanceMessage = "Inactive partial transfer cache cleared. Active playback was preserved." }
                    }
                    Button("Clear cached artwork", systemImage: "photo.on.rectangle") {
                        Task {
                            await ArtworkCacheMaintenance.clear()
                            maintenanceMessage = "Artwork cache cleared. Posters download again when needed."
                        }
                    }
                    Button("Clear cached provider metadata", systemImage: "network") {
                        Task {
                            await SourceDiscoveryCache.shared.clear()
                            maintenanceMessage = "Cached provider metadata cleared. New searches fetch fresh responses; active playback continues."
                        }
                    }
                    Button("Clear cached catalog", systemImage: "arrow.clockwise") { showingClearConfirmation = true }
                    if let maintenanceMessage { Text(maintenanceMessage).font(.caption).foregroundStyle(.secondary) }
                    Text("CineNex \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")")
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }.padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAppearance) { AppearanceSettingsView() }
        .confirmationDialog("Clear the cached catalog?", isPresented: $showingClearConfirmation) {
            Button("Clear cached catalog") { CatalogCacheStore.shared.clear(); maintenanceMessage = "Cache cleared. Pull down on Home to fetch fresh metadata." }
        } message: { Text("Saved titles, playback progress and account settings are retained.") }
        .tint(Color.cineNexAccent)
    }

    private func settingsLink(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(Color.cineNexAccent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CineNexProviderSettingsView: View {
    @State private var manifests = ""
    @State private var message: String?
    @State private var failed = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Label("Torrentio", systemImage: "network")
                Label("MediaFusion", systemImage: "play.rectangle.on.rectangle")
                Text("CineNex searches Torrentio and MediaFusion separately. Leaving the configuration empty uses the bundled endpoints. A configured MediaFusion manifest can include your own provider preferences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Playback providers")
            }
            Section {
                TextEditor(text: $manifests)
                    .frame(minHeight: 170)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityLabel("Add-on manifest URLs, one per line")
                Button("Save provider configuration", action: save)
                    .disabled(!loaded)
                if let message {
                    Label(message, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(failed ? Color.orange : Color.green)
                        .font(.footnote)
                }
            } header: {
                Text("Custom manifest URLs")
            } footer: {
                Text("Enter one HTTPS manifest.json URL per line. URLs may contain private configuration and are saved in Keychain. Changes apply to newly opened Watch screens.")
            }
            Section("Configure a provider") {
                Link("Configure Torrentio", destination: URL(string: "https://torrentio.strem.fun/configure")!)
                Link("MediaFusion", destination: URL(string: "https://mediafusion.elfhosted.com")!)
            }
        }
        .navigationTitle("Sources & providers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            do {
                manifests = try StremioAddonConfigurationStore.load() ?? ""
                loaded = true
            } catch {
                failed = true
                message = error.localizedDescription
            }
        }
    }

    private func save() {
        let lines = manifests.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.allSatisfy({ line in
            guard let url = URL(string: line) else { return false }
            return StremioAddonClient.isSafeHTTPSURL(url) && url.path.hasSuffix("/manifest.json")
        }) else {
            failed = true
            message = "Every entry must be an HTTPS URL ending in /manifest.json."
            return
        }
        var seen = Set<String>()
        let normalized = lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        do {
            try StremioAddonConfigurationStore.save(normalized)
            manifests = normalized
            failed = false
            message = normalized.isEmpty ? "Default providers restored." : "Provider configuration saved."
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}
