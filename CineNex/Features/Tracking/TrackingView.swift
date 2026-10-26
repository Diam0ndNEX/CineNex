import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TrackingView: View {
    @StateObject private var trakt = TraktIntegration.shared
    @State private var scrobblingEnabled = UserDefaults.standard.bool(forKey: "cinenex.traktScrobbleEnabled")
    @StateObject private var letterboxd = LetterboxdLibraryStore.shared
    @State private var importingLetterboxd = false
    @State private var exportingLetterboxd = false
    @State private var exportDocument = LetterboxdCSVDocument()
    @State private var exportFilename = "diary"
    @State private var letterboxdMessage: String?
    @State private var tmdbToken = TMDBTokenStore.load() ?? ""
    @State private var tmdbMessage: String?
    @State private var testingTMDBConnection = false
    @StateObject private var traktWatchlist = TraktWatchlistStore.shared
    @State private var remoteWatchlist: [TraktWatchlistMovie] = []
    @State private var showingTraktWatchlistReview = false
    @State private var loadingTraktWatchlist = false
    @State private var watchlistMessage: String?
    @StateObject private var traktHistory = TraktHistoryStore.shared
    @State private var remoteHistory: [TraktHistoryMovie] = []
    @State private var showingTraktHistoryReview = false
    @State private var loadingTraktHistory = false
    @State private var historyMessage: String?
    @StateObject private var traktRatings = TraktRatingStore.shared
    @State private var remoteRatings: [TraktRatingMovie] = []
    @State private var showingTraktRatingsReview = false
    @State private var loadingTraktRatings = false
    @State private var ratingsMessage: String?
    @State private var showingPrivacyDetails = false
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

                tmdbCard
                AccountConnectionsView()
                traktCard
                traktWatchlistCard
                traktHistoryCard
                traktRatingsCard
                letterboxdCard

                VStack(alignment: .leading, spacing: 8) {
                    Label("Your data stays yours", systemImage: "lock.shield")
                        .font(.headline)
                    Text("CineNex keeps local playback progress on this device. Trakt and TMDB access tokens are stored in iOS Keychain. Disconnecting either service removes its saved token.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        showingPrivacyDetails = true
                    } label: {
                        Label("View data and privacy details", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityHint("Explains what CineNex stores locally and what is shared with connected services.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
        }
        .background(Color.cineNexBackground.ignoresSafeArea())
        .onDisappear { trakt.cancelDeviceSignIn() }
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPrivacyDetails) {
            NavigationStack {
                CineNexPrivacyDetailsView()
            }
        }
        .onChange(of: scrobblingEnabled) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "cinenex.traktScrobbleEnabled")
        }
        .fileImporter(
            isPresented: $importingLetterboxd,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true,
            onCompletion: importLetterboxdFiles
        )
        .fileExporter(
            isPresented: $exportingLetterboxd,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename,
            onCompletion: finishLetterboxdExport
        )

    }

    private var tmdbCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.tv")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.cineNexAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Catalog")
                        .font(.title2.bold())
                    Text(tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Using local demo titles" : "TMDB token saved")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Connect TMDB to replace the sample catalog with trending movies and series, real descriptions, ratings, release years, and poster artwork. TMDB supplies metadata only; it does not supply playable streams.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("TMDB Read Access Token", text: $tmdbToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("TMDB Read Access Token")

            HStack(spacing: 10) {
                Button {
                    let token = tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        try TMDBTokenStore.save(token)
                        tmdbToken = token
                        tmdbMessage = token.isEmpty
                            ? "Live catalog disabled. CineNex will use its local demo catalog."
                            : "Token saved securely. Return to Home and tap refresh to load trending titles."
                    } catch {
                        tmdbMessage = "Could not securely save the TMDB token: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Save token", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    do {
                        try TMDBTokenStore.delete()
                        tmdbToken = ""
                        tmdbMessage = "TMDB disconnected. CineNex will use its local demo catalog."
                    } catch {
                        tmdbMessage = "Could not remove the saved TMDB token: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Disconnect", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await testTMDBConnection() }
            } label: {
                HStack(spacing: 8) {
                    if testingTMDBConnection {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.shield")
                    }
                    Text(testingTMDBConnection ? "Testing connection…" : "Test connection")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(testingTMDBConnection || tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Checks whether the entered TMDB Read Access Token can load catalog metadata.")

            if let tmdbMessage {
                Text(tmdbMessage)
                    .font(.footnote)
                    .foregroundColor(tmdbMessage.localizedCaseInsensitiveContains("could not") || tmdbMessage.localizedCaseInsensitiveContains("rejected") || tmdbMessage.localizedCaseInsensitiveContains("failed") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openURL(URL(string: "https://www.themoviedb.org/settings/api")!)
            } label: {
                Label("Get a TMDB API token", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
            }

            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(URL(string: "https://www.themoviedb.org/")!)
            } label: {
                Label("About TMDB", systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
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
                        .foregroundColor(trakt.isConnected ? .green : .secondary)
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

            if !trakt.loginAvailable, !trakt.isConnected {
                Text("Trakt login needs to be enabled in this CineNex build. No API credentials are required from you.")
                    .font(.caption).foregroundStyle(.secondary)
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

            if trakt.isAuthorizing {
                ProgressView(trakt.activeAuthorization == nil ? "Requesting sign-in code…" : "Waiting for approval on Trakt…")
                    .font(.caption)
                Button("Cancel sign-in", role: .cancel) { trakt.cancelDeviceSignIn() }
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
                    trakt.startDeviceSignIn()
                } label: {
                    Label(trakt.isAuthorizing ? "Waiting for Trakt sign-in…" : "Sign in to Trakt", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!trakt.loginAvailable || trakt.isAuthorizing)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var traktWatchlistCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "list.star")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.cineNexAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trakt Watchlist")
                        .font(.title2.bold())
                    Text("\(traktWatchlist.entries.count) saved locally")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Fetch your Trakt movie watchlist, review the entries, and import selected titles into a separate CineNex watchlist stored on this device. Importing never edits your Trakt account or your favorites.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !traktWatchlist.entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(traktWatchlist.entries.prefix(5)) { entry in
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.cineNexAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                Text([entry.year.map(String.init), entry.tmdbID.map { "TMDB \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                traktWatchlist.remove(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(entry.title) from local watchlist")
                        }
                    }
                }
            }

            Button {
                loadingTraktWatchlist = true
                watchlistMessage = nil
                Task {
                    do {
                        remoteWatchlist = try await trakt.fetchMovieWatchlist()
                        showingTraktWatchlistReview = true
                        if remoteWatchlist.isEmpty {
                            watchlistMessage = "Your Trakt movie watchlist is empty."
                        }
                    } catch {
                        watchlistMessage = error.localizedDescription
                    }
                    loadingTraktWatchlist = false
                }
            } label: {
                if loadingTraktWatchlist {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Fetch and review Trakt watchlist", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!trakt.isConnected || loadingTraktWatchlist)

            if let watchlistMessage {
                Text(watchlistMessage)
                    .font(.footnote)
                    .foregroundStyle(watchlistMessage.localizedCaseInsensitiveContains("failed") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .sheet(isPresented: $showingTraktWatchlistReview) {
            TraktWatchlistReviewView(movies: remoteWatchlist, store: traktWatchlist)
        }
    }

    private var traktHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.cineNexAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trakt Watch History")
                        .font(.title2.bold())
                    Text("\(traktHistory.entries.count) watched locally")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Fetch your watched movies from Trakt, review the history, and import selected records into CineNex’s separate local watched history. This does not alter Trakt or playback resume progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !traktHistory.entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(traktHistory.entries.prefix(5)) { entry in
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.cineNexAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                Text([entry.year.map(String.init), entry.watchedAt.map { String($0.prefix(10)) }, entry.plays > 1 ? "\(entry.plays) plays" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                traktHistory.remove(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(entry.title) from local watched history")
                        }
                    }
                }
            }

            Button {
                loadingTraktHistory = true
                historyMessage = nil
                Task {
                    do {
                        remoteHistory = try await trakt.fetchMovieHistory()
                        if remoteHistory.isEmpty {
                            historyMessage = "Your Trakt movie history is empty."
                        } else {
                            showingTraktHistoryReview = true
                        }
                    } catch {
                        historyMessage = error.localizedDescription
                    }
                    loadingTraktHistory = false
                }
            } label: {
                if loadingTraktHistory {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Fetch and review Trakt history", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!trakt.isConnected || loadingTraktHistory)

            if let historyMessage {
                Text(historyMessage)
                    .font(.footnote)
                    .foregroundStyle(historyMessage.localizedCaseInsensitiveContains("failed") || historyMessage.localizedCaseInsensitiveContains("error") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .sheet(isPresented: $showingTraktHistoryReview) {
            TraktHistoryReviewView(movies: remoteHistory, store: traktHistory)
        }
    }

    private var traktRatingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "star.leadinghalf.filled")
                    .font(.title2)
                    .foregroundStyle(Color.cineNexAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.cineNexAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trakt Movie Ratings")
                        .font(.title2.bold())
                    Text("\(traktRatings.entries.count) ratings saved locally")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Fetch your movie ratings from Trakt, review them, and import selected ratings into CineNex’s local rating list. This is a one-way import: it does not rate or change anything on Trakt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !traktRatings.entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(traktRatings.entries.prefix(5)) { entry in
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.cineNexAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                Text([entry.year.map(String.init), "\(entry.rating)/10 ★", entry.ratedAt.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                traktRatings.remove(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(entry.title) from local ratings")
                        }
                    }
                }
            }

            Button {
                loadingTraktRatings = true
                ratingsMessage = nil
                Task {
                    do {
                        remoteRatings = try await trakt.fetchMovieRatings()
                        if remoteRatings.isEmpty {
                            ratingsMessage = "No valid movie ratings were found in your Trakt account."
                        } else {
                            showingTraktRatingsReview = true
                        }
                    } catch {
                        ratingsMessage = error.localizedDescription
                    }
                    loadingTraktRatings = false
                }
            } label: {
                if loadingTraktRatings {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Fetch and review Trakt ratings", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!trakt.isConnected || loadingTraktRatings)

            if let ratingsMessage {
                Text(ratingsMessage)
                    .font(.footnote)
                    .foregroundStyle(ratingsMessage.localizedCaseInsensitiveContains("failed") || ratingsMessage.localizedCaseInsensitiveContains("error") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 22))
        .sheet(isPresented: $showingTraktRatingsReview) {
            TraktRatingsReviewView(movies: remoteRatings, store: traktRatings)
        }
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

            Label("Import your official Letterboxd CSV exports, keep a local copy of your diary, and export diary.csv for reuse. Direct account sync requires Letterboxd API access.", systemImage: "arrow.left.arrow.right")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label("\(letterboxd.records.count) imported rows", systemImage: "tray.full")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(letterboxd.diaryRecords.count) diary entries")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if !letterboxd.diaryRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(letterboxd.diaryRecords.prefix(4)) { record in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 0.45))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.subheadline.weight(.semibold))
                                Text([record.year.map(String.init), record.watchedDate, record.rating.map { "\(String(format: "%g", $0)) ★" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    importingLetterboxd = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Diary (diary.csv)") { beginLetterboxdExport(kind: .diary) }
                        .disabled(!letterboxd.records.contains { $0.kind == .diary })
                    Button("Watched (watched.csv)") { beginLetterboxdExport(kind: .watched) }
                        .disabled(!letterboxd.records.contains { $0.kind == .watched })
                    Button("Ratings (ratings.csv)") { beginLetterboxdExport(kind: .ratings) }
                        .disabled(!letterboxd.records.contains { $0.kind == .ratings })
                    Button("Watchlist (watchlist.csv)") { beginLetterboxdExport(kind: .watchlist) }
                        .disabled(!letterboxd.records.contains { $0.kind == .watchlist })
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!letterboxd.records.contains { $0.kind != .other })
            }

            if let letterboxdMessage {
                Text(letterboxdMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    @MainActor
    private func testTMDBConnection() async {
        let token = tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            tmdbMessage = "Enter a TMDB Read Access Token before testing the connection."
            return
        }

        testingTMDBConnection = true
        tmdbMessage = nil
        defer { testingTMDBConnection = false }

        do {
            let items = try await TMDBCatalogProvider(readAccessToken: token).fetchCatalog()
            if items.isEmpty {
                tmdbMessage = "TMDB accepted the token, but returned no usable trending titles."
            } else {
                tmdbMessage = "Connection successful. TMDB returned \(items.count) trending titles. Save the token to use the live catalog."
            }
        } catch {
            tmdbMessage = "Connection test failed: \(error.localizedDescription)"
        }
    }

    private func importLetterboxdFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            letterboxdMessage = "Import cancelled or failed: \(error.localizedDescription)"
        case .success(let urls):
            var importedRows = 0
            var skippedFiles: [String] = []
            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw LetterboxdCSVError.unreadableText
                    }
                    importedRows += try letterboxd.importCSV(text, filename: url.lastPathComponent)
                } catch {
                    skippedFiles.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if skippedFiles.isEmpty {
                letterboxdMessage = "Import complete. Added \(importedRows) new rows; duplicate rows were merged."
            } else {
                letterboxdMessage = "Added \(importedRows) new rows. Some files could not be imported: " + skippedFiles.joined(separator: " · ")
            }
        }
    }

    private func beginLetterboxdExport(kind: LetterboxdRecordKind) {
        exportFilename = kind.rawValue
        exportDocument = LetterboxdCSVDocument(data: letterboxd.makeCSVExport(for: kind))
        exportingLetterboxd = true
    }

    private func finishLetterboxdExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            letterboxdMessage = "\(exportFilename.capitalized) CSV exported. Import it into Letterboxd using its official import tools."
        case .failure(let error):
            letterboxdMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func openTraktDeveloper() {
        openURL(URL(string: "https://trakt.tv/oauth/applications")!)
    }

    private func traktError(_ error: Error) {
        trakt.reportSetupError(error)
    }
}

private struct CineNexPrivacyDetailsView: View {
    var body: some View {
        List {
            Section("Stored on this device") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Playback and favorites")
                            .font(.headline)
                        Text("Resume positions, favorites, and imported watch-list records are kept in local app storage. Playback progress is not automatically synced between devices.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "iphone")
                        .foregroundStyle(Color.cineNexAccent)
                }

                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Imported Letterboxd files")
                            .font(.headline)
                        Text("CSV data is imported when you choose files. CineNex does not sign in to Letterboxd or upload those files to a CineNex account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.cineNexAccent)
                }
            }

            Section("Connected services") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TMDB")
                            .font(.headline)
                        Text("When you connect TMDB, CineNex sends catalog searches and metadata requests to TMDB. The access token is stored in iOS Keychain. TMDB provides metadata, not playable media.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles.tv")
                        .foregroundStyle(Color.cineNexAccent)
                }

                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trakt")
                            .font(.headline)
                        Text("Your authorization token is stored in iOS Keychain. If you enable scrobbling, supported movie playback events are sent to Trakt. You can disconnect Trakt from this screen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.cineNexAccent)
                }
            }

            Section("Your choices") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optional integrations")
                            .font(.headline)
                        Text("TMDB and Trakt connections are optional. Disconnecting removes the corresponding saved token; it does not delete data already held by those services.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "hand.raised")
                        .foregroundStyle(Color.cineNexAccent)
                }
            }
        }
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TrackingView()
    }
}
