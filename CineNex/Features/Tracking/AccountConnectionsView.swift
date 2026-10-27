import SwiftUI

struct AccountConnectionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            AnimeAccountCard(provider: .aniList)
            AnimeAccountCard(provider: .myAnimeList)
        }
    }
}

private struct AnimeAccountCard: View {
    let provider: AnimeAccountProvider
    @StateObject private var account: AnimeAccountIntegration
    @State private var showsList = false
    init(provider: AnimeAccountProvider) {
        self.provider = provider
        _account = StateObject(wrappedValue: AnimeAccountIntegration(provider: provider))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(provider.title, systemImage: "person.crop.circle.badge.checkmark").font(.title2.bold())
                Spacer()
                if account.isWorking { ProgressView() }
            }
            if let name = account.userName {
                Label("Signed in as \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(account.entries.count) anime list entries loaded").font(.caption).foregroundStyle(.secondary)
                Button("View account list") { showsList = true }
                Button("Refresh list") { Task { await account.refresh() } }.disabled(account.isWorking)
            } else {
                Text("Sign in on \(provider.title) to view your anime list. Your password is entered only on the service's website.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if account.isConfigured {
                    Button("Sign in to \(provider.title)") { Task { await account.signIn() } }
                        .buttonStyle(.borderedProminent).disabled(account.isWorking)
                } else {
                    Label("Sign-in unavailable in this build", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("CineNex's \(provider.title) application registration is not complete. No API key is required from you. Login will be available in a build that includes the registered application.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if account.hasSavedSession {
                Button("Disconnect \(provider.title)", role: .destructive) { account.disconnect() }.disabled(account.isWorking)
            }
            if let message = account.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .task { await account.refresh() }
        .sheet(isPresented: $showsList) {
            NavigationStack {
                List(account.entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(.headline)
                        Text("\(entry.watchedEpisodes) episodes · \(entry.status.replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(provider.title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsList = false } } }
            }
        }
    }
}
