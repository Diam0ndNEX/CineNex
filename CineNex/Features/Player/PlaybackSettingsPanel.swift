import AVFoundation
import AVKit
import SwiftUI

struct PlaybackSettingsPanel: View {
    let player: AVPlayer
    let audioOptions: [AVMediaSelectionOption]
    let subtitleOptions: [AVMediaSelectionOption]
    let audioGroup: AVMediaSelectionGroup?
    let subtitleGroup: AVMediaSelectionGroup?
    @Binding var videoGravity: AVLayerVideoGravity
    @Binding var playbackRate: Float
    let onClose: () -> Void

    private let playbackRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        NavigationStack {
            List {
                Section("Playback speed") {
                    ForEach(playbackRates, id: \.self) { rate in
                        Button {
                            playbackRate = rate
                            if player.rate != 0 {
                                player.rate = rate
                            }
                        } label: {
                            HStack {
                                Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if abs(playbackRate - rate) < 0.01 {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Picture") {
                    gravityOption("Fit", gravity: .resizeAspect)
                    gravityOption("Fill", gravity: .resizeAspectFill)
                    gravityOption("Stretch", gravity: .resize)
                }

                if !audioOptions.isEmpty, let audioGroup {
                    Section("Audio track") {
                        ForEach(Array(audioOptions.enumerated()), id: \.offset) { entry in
                            Button {
                                player.currentItem?.select(entry.element, in: audioGroup)
                            } label: {
                                HStack {
                                    Text(entry.element.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if player.currentItem?.currentMediaSelection.selectedMediaOption(in: audioGroup) == entry.element {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !subtitleOptions.isEmpty, let subtitleGroup {
                    Section("Subtitles") {
                        Button {
                            player.currentItem?.select(nil, in: subtitleGroup)
                        } label: {
                            HStack {
                                Text("Off").foregroundStyle(.primary)
                                Spacer()
                                if player.currentItem?.currentMediaSelection.selectedMediaOption(in: subtitleGroup) == nil {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ForEach(Array(subtitleOptions.enumerated()), id: \.offset) { entry in
                            Button {
                                player.currentItem?.select(entry.element, in: subtitleGroup)
                            } label: {
                                HStack {
                                    Text(entry.element.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if player.currentItem?.currentMediaSelection.selectedMediaOption(in: subtitleGroup) == entry.element {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Text("Available audio and subtitle tracks depend on the selected source.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Playback settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    private func gravityOption(_ title: String, gravity: AVLayerVideoGravity) -> some View {
        Button {
            videoGravity = gravity
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if videoGravity == gravity {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
