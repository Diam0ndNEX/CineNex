import SwiftUI

private enum CineNexAccentPreset: String, CaseIterable, Identifiable {
    case violet
    case blue
    case rose
    case teal
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .violet: return "Violet"
        case .blue: return "Blue"
        case .rose: return "Rose"
        case .teal: return "Teal"
        case .amber: return "Amber"
        }
    }

    var color: Color {
        switch self {
        case .violet:
            return Color(red: 0.58, green: 0.36, blue: 0.98)
        case .blue:
            return Color(red: 0.24, green: 0.52, blue: 1.0)
        case .rose:
            return Color(red: 0.95, green: 0.32, blue: 0.58)
        case .teal:
            return Color(red: 0.12, green: 0.72, blue: 0.68)
        case .amber:
            return Color(red: 1.0, green: 0.62, blue: 0.22)
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("cinenex.accentPreset") private var selectedAccent = CineNexAccentPreset.violet.rawValue
    @Environment(\.dismiss) private var dismiss

    private var accent: CineNexAccentPreset {
        CineNexAccentPreset(rawValue: selectedAccent) ?? .violet
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Make it yours")
                            .font(.title2.bold())
                        Text("Choose an accent that carries through buttons, selection states, and playback progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent color")
                            .font(.headline)

                        HStack(spacing: 0) {
                            ForEach(CineNexAccentPreset.allCases) { preset in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedAccent = preset.rawValue
                                    }
                                } label: {
                                    VStack(spacing: 9) {
                                        ZStack {
                                            Circle()
                                                .fill(preset.color)
                                                .frame(width: 42, height: 42)
                                            if selectedAccent == preset.rawValue {
                                                Image(systemName: "checkmark")
                                                    .font(.headline.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .overlay {
                                            Circle()
                                                .strokeBorder(
                                                    selectedAccent == preset.rawValue ? Color.primary.opacity(0.8) : Color.clear,
                                                    lineWidth: 2
                                                )
                                                .padding(-4)
                                        }

                                        Text(preset.title)
                                            .font(.caption.weight(selectedAccent == preset.rawValue ? .semibold : .regular))
                                            .foregroundStyle(selectedAccent == preset.rawValue ? .primary : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(preset.title) accent")
                                .accessibilityAddTraits(selectedAccent == preset.rawValue ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .font(.headline)

                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                                .foregroundStyle(accent.color)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("CineNex")
                                    .font(.headline)
                                Text("Your next favorite is waiting")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(accent.color)
                        }
                        .padding(16)
                        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 16))

                        Button {} label: {
                            Label("Accent preview", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(accent.color, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                        .accessibilityLabel("Preview of the selected accent color")
                    }
                }
                .padding(20)
            }
            .background(Color.cineNexBackground.ignoresSafeArea())
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(accent.color)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AppearanceSettingsView()
}
