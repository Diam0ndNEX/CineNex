import SwiftUI

/// Native release cards with provider pinning and concise, reported metadata.
struct SourceReleaseCard: View {
    let descriptor: StremioTorrentDescriptor
    let isPreparing: Bool
    let isDisabled: Bool
    var statusMessage: String? = nil
    var isPinned = false
    var onTogglePin: (() -> Void)? = nil
    let onPlay: () -> Void
    @AppStorage("cinenex.sourceCardDensity") private var density = "comfortable"
    @AppStorage("cinenex.showSourceTechnicalLabels") private var showTechnicalLabels = true
    @State private var showsDetails = false

    private var title: String {
        let firstLine = descriptor.title.split(whereSeparator: \.isNewline).first.map(String.init) ?? descriptor.title
        let metadataStart = [firstLine.range(of: "👤")?.lowerBound, firstLine.range(of: "💾")?.lowerBound]
            .compactMap { $0 }.min()
        let name = metadataStart.map { String(firstLine[..<$0]) } ?? firstLine
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Torrent release" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(descriptor.providerName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cineNexAccent)
                        if let onTogglePin {
                            Button(action: onTogglePin) {
                                Image(systemName: isPinned ? "pin.fill" : "pin")
                                    .font(.caption).frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isPinned ? Color.cineNexAccent : Color.secondary)
                            .accessibilityLabel("\(isPinned ? "Unpin" : "Pin") provider \(descriptor.providerName)")
                        }
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(density == "compact" ? 1 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onPlay) {
                    Group {
                        if isPreparing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .frame(width: 46, height: 46)
                    .cineNexGlass(in: Circle(), prominent: true)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel("Play \(title) from \(descriptor.providerName)")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { metadata }
                VStack(alignment: .leading, spacing: 6) { metadata }
            }
            if showTechnicalLabels {
                let labels = ReleaseTechnicalLabels.labels(in: descriptor.title)
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · "))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if let statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
            if density != "compact" {
                DisclosureGroup(isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(descriptor.title)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(descriptor.fileIndex.map { "Video file \($0 + 1) in the release" } ?? "CineNex will select the largest supported video")
                            .font(.caption2)
                        Text("Codec, HDR and audio labels come from the release name; playback compatibility is checked separately.")
                            .font(.caption)
                        Text("Peer counts are reported by the source and can change. Availability is checked when you connect.")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                } label: {
                    Text(showsDetails ? "Hide release details" : "Release details")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .tint(.secondary)
            }
        }
        .padding(density == "compact" ? 12 : 16)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isPreparing ? Color.cineNexAccent.opacity(0.65) : Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if let resolution = SceneBoxStreamPicker.resolution(for: descriptor) {
            SourceMetadataChip(title: resolution.uppercased(), symbol: "viewfinder")
        }
        if let size = SceneBoxStreamPicker.size(for: descriptor), !size.isEmpty {
            SourceMetadataChip(title: size, symbol: "internaldrive")
        } else {
            SourceMetadataChip(title: "Size not supplied", symbol: "internaldrive")
        }
        if let seeders = SceneBoxStreamPicker.seeders(for: descriptor) {
            SourceMetadataChip(title: "\(seeders) seeders", symbol: "person.2", tint: seeders >= 5 ? .green : .orange)
        } else {
            SourceMetadataChip(title: "Peers unknown", symbol: "person.2")
        }
    }
}

struct SourceMetadataChip: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.09), in: Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
