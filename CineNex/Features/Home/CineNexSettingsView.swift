import SwiftUI

/// Adapts SceneBox's grouped playback and appearance preferences to CineNex stores.
struct CineNexSettingsView: View {
    @State private var showingAppearance = false
    @AppStorage("cinenex.preferredSubtitleLanguage") private var subtitleLanguage = SubtitleLanguage.deviceDefault.code

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Make CineNex yours", systemImage: "play.rectangle.fill")
                        .font(.title2.bold())
                    Text("Your playback, your library, your preferences.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            Section("Playback") {
                NavigationLink {
                    CineNexProviderSettingsView()
                } label: {
                    Label("Sources & providers", systemImage: "network")
                }
                Picker(selection: $subtitleLanguage) {
                    ForEach(SubtitleLanguage.offered) { language in
                        Text(language.name).tag(language.code)
                    }
                } label: {
                    Label("Subtitle language", systemImage: "captions.bubble")
                }
            }
            Section("Personalization") {
                Button {
                    showingAppearance = true
                } label: {
                    Label("Appearance & layout", systemImage: "paintpalette")
                }
                NavigationLink {
                    TrackingView()
                } label: {
                    Label("Accounts & tracking", systemImage: "person.crop.circle")
                }
            }
            Section {
                Text("Subtitle preferences apply when opening a player. Configure Torrentio and MediaFusion in Sources & providers; source availability is shown when you open a title.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cineNexBackground.ignoresSafeArea())
        .sheet(isPresented: $showingAppearance) { AppearanceSettingsView() }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .tint(Color.cineNexAccent)
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
