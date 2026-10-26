import SwiftUI
import SwiftVLC

struct VLCPlaybackSettingsPanel: View {
    let player: Player
    let subtitles: SubtitlesController
    let onClose: () -> Void

    private enum Page {
        case playback
        case subtitles
    }

    @State private var page: Page = .playback
    private let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(title: page == .playback ? "Playback" : "Subtitles")
                    if page == .playback {
                        audioSection
                        subtitleNavigation
                        if hasActiveSubtitle {
                            subtitleDelaySection
                        }
                        speedSection
                        aspectSection
                    } else {
                        subtitleSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 360, maxHeight: .infinity)
            .background(Color.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(12)
        }
        .foregroundStyle(.primary)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.15), value: page == .playback)
    }

    private func header(title: String) -> some View {
        HStack(spacing: 14) {
            if page == .subtitles {
                Button {
                    page = .playback
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if page == .playback {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close playback settings")
            }
        }
    }

    private var audioSection: some View {
        settingsSection(title: "Audio") {
            let tracks = uniqueTracks(player.audioTracks)
            if tracks.isEmpty {
                Text("No audio tracks reported by this source.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tracks) { track in
                    optionRow(
                        title: trackLabel(track),
                        selected: player.selectedAudioTrack?.id == track.id
                    ) {
                        player.selectedAudioTrack = track
                    }
                }
            }
        }
    }

    private var subtitleNavigation: some View {
        settingsSection(title: "Subtitles") {
            Button {
                page = .subtitles
            } label: {
                HStack {
                    Text("Language")
                    Spacer()
                    Text(currentSubtitleLabel)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitleSection: some View {
        settingsSection(title: "Language") {
            optionRow(title: "Off", selected: !hasActiveSubtitle) {
                subtitles.apply(nil, on: player)
            }

            ForEach(subtitles.embeddedTracks(of: player)) { track in
                optionRow(
                    title: trackLabel(track),
                    selected: subtitles.embeddedID == track.id
                ) {
                    subtitles.selectEmbedded(track, on: player)
                }
            }

            if subtitles.isLoading {
                Label("Finding subtitles…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(subtitles.byLanguage, id: \.language) { group in
                if let track = group.tracks.first {
                    optionRow(
                        title: group.language,
                        selected: group.tracks.contains { $0.id == subtitles.selectedID }
                    ) {
                        subtitles.apply(track, on: player)
                    }
                }
            }

            if !subtitles.isLoading,
               subtitles.byLanguage.isEmpty,
               subtitles.embeddedTracks(of: player).isEmpty {
                Text("No embedded or external subtitles are available for this source.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitleDelaySection: some View {
        settingsSection(title: "Subtitle sync") {
            HStack(spacing: 16) {
                Button {
                    adjustSubtitleDelay(by: -0.25)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show subtitles 0.25 seconds earlier")

                VStack(spacing: 2) {
                    Text(delayText).font(.headline.monospacedDigit())
                    Text(delayHint).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    adjustSubtitleDelay(by: 0.25)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show subtitles 0.25 seconds later")
            }
        }
    }

    private var speedSection: some View {
        settingsSection(title: "Speed") {
            ForEach(rates, id: \.self) { rate in
                optionRow(
                    title: String(format: "%.2g×", rate),
                    selected: abs(player.rate - rate) < 0.01
                ) {
                    try? player.setPlaybackRate(PlaybackRate(rate))
                }
            }
        }
    }

    private var aspectSection: some View {
        settingsSection(title: "Aspect ratio") {
            aspectRow("Fit", .default)
            aspectRow("Fill", .fill)
            aspectRow("16:9", .ratio(16, 9))
            aspectRow("4:3", .ratio(4, 3))
        }
    }

    private func aspectRow(_ title: String, _ ratio: AspectRatio) -> some View {
        optionRow(title: title, selected: player.aspectRatio == ratio) {
            player.aspectRatio = ratio
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func optionRow(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(2)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private func trackLabel(_ track: Track) -> String {
        let language = track.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !language.isEmpty && !name.localizedCaseInsensitiveContains(language) {
            return "\(name) · \(language)"
        }
        if !name.isEmpty { return name }
        if !language.isEmpty { return SubtitleLanguage.displayName(for: language) }
        return "Track"
    }

    private var hasActiveSubtitle: Bool {
        subtitles.embeddedID != nil || subtitles.selectedID != nil
    }

    private var currentSubtitleLabel: String {
        if let id = subtitles.embeddedID,
           let track = subtitles.embeddedTracks(of: player).first(where: { $0.id == id }) {
            return trackLabel(track)
        }
        if let group = subtitles.byLanguage.first(where: { group in
            group.tracks.contains { $0.id == subtitles.selectedID }
        }) {
            return group.language
        }
        if let selected = player.selectedSubtitleTrack {
            return trackLabel(selected)
        }
        return "Off"
    }

    private var delaySeconds: Double {
        let components = player.subtitleDelay.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private var delayText: String {
        String(format: "%+.2f s", delaySeconds)
    }

    private var delayHint: String {
        if abs(delaySeconds) < 0.01 { return "in sync" }
        return delaySeconds > 0 ? "later" : "earlier"
    }

    private func adjustSubtitleDelay(by seconds: Double) {
        let milliseconds = Int((delaySeconds + seconds) * 1000)
        try? player.setSubtitleDelay(.milliseconds(milliseconds))
    }
}
