import SwiftUI
import UIKit

struct TrackingView: View {
    @StateObject private var trakt = TraktIntegration.shared
    @State private var clientID = TraktIntegration.shared.savedClientID
    @State private var scrobblingEnabled = UserDefaults.standard.bool(forKey: "cinenex.traktScrobbleEnabled")
    @State private var showingSetupHelp = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tracking")
                        .font(.largeTitle.bold())
                    Text("Connect your watch history and film diary services.")
                        .foregroundStyle(.secondary)
                }

                traktCard
                letterboxdCard

                VStack(alignment: .leading, spacing: 8) {
                    Label("Your data stays yours", systemImage: "lock.shield")
                        .font(.headline)
                    Text("CineNex keeps local playback progress on this device. Trakt access tokens are stored in iOS Keychain. Disconnecting Trakt removes the saved token.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scrobblingEnabled) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "cinenex.traktScrobbleEnabled")
        }
        .alert("Set up Trakt", isPresented: $showingSetupHelp) {
            Button("Open Trakt Developer", action: openTraktDeveloper)
            Button("Done", role: .cancel) {}
        } message: {
            Text("Create an API application on Trakt, copy its Client ID into this screen, and then connect your account. CineNex uses the device authorization flow and does not ask for your Trakt password.")
        }
    }

    private var traktCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.cineNexAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trakt")
                        .font(.title2.bold())
                    Text(trakt.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(trakt.isConnected ? .green : .secondary)
                }
                Spacer()
                if trakt.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text("Sync supported movie playback to your Trakt history. Episode scrobbling will be enabled when CineNex has real season and episode metadata.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Trakt API Client ID")
                    .font(.subheadline.weight(.semibold))
                SecureField("Paste your Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                Button("How to get a Client ID") {
                    showingSetupHelp = true
                }
                .font(.footnote.weight(.medium))
            }

            Toggle(isOn: $scrobblingEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Automatically scrobble playback")
                        .font(.subheadline.weight(.semibold))
                    Text("Send start and stop events when a supported movie plays.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.cineNexAccent)
            .disabled(!trakt.isConnected)

            if let authorization = trakt.activeAuthorization {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter this code on Trakt")
                        .font(.subheadline.weight(.semibold))
                    Text(authorization.userCode)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospaced())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        UIPasteboard.general.string = authorization.userCode
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                    }
                    .font(.subheadline.weight(.medium))
                    Button {
                        openURL(authorization.verificationURL)
                    } label: {
                        Label("Open Trakt authorization", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color.cineNexAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }

            if let error = trakt.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if trakt.isConnected {
                Button(role: .destructive) {
                    trakt.disconnect()
                    scrobblingEnabled = false
                } label: {
                    Label("Disconnect Trakt", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task {
                        do {
                            let authorization = try await trakt.requestDeviceAuthorization(clientID: clientID)
                            let pollingTask = Task {
                                await trakt.completeDeviceAuthorization(authorization)
                            }
                            _ = await pollingTask.value
                        } catch {
                            traktError(error)
                        }
                    }
                } label: {
                    Label(trakt.activeAuthorization == nil ? "Connect Trakt" : "Waiting for authorization…", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || trakt.activeAuthorization != nil)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var letterboxdCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 0.45))
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.45, green: 0.78, blue: 0.45).opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Letterboxd")
                        .font(.title2.bold())
                    Text("Film diary, ratings and watchlist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Letterboxd’s API access is currently request-only, and its published policy says private/personal projects are not being granted access. CineNex won’t ask for your Letterboxd password or scrape the website.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label("Planned: import/export your Letterboxd diary and ratings using Letterboxd’s official data export, with duplicate-safe matching.", systemImage: "arrow.left.arrow.right")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(URL(string: "https://letterboxd.com/")!)
            } label: {
                Label("Open Letterboxd", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                openURL(URL(string: "https://letterboxd.com/api-beta/access/")!)
            } label: {
                Label("Letterboxd API access information", systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func openTraktDeveloper() {
        openURL(URL(string: "https://trakt.tv/oauth/applications")!)
    }

    private func traktError(_ error: Error) {
        trakt.reportSetupError(error)
    }
}

#Preview {
    NavigationStack {
        TrackingView()
    }
}
