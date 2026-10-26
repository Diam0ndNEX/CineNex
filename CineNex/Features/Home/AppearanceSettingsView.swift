import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.accentPreset") private var accent = "violet"
    @AppStorage("cinenex.canvasStyle") private var canvas = "midnight"
    @AppStorage("cinenex.posterDensity") private var density = "comfortable"
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @AppStorage("cinenex.reduceMotion") private var reduceMotion = false
    private let accents = ["violet", "blue", "rose", "teal", "amber", "lime"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Make it feel like you.").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Live choices for your personal cinema.").foregroundStyle(.secondary)
                    CineNexPreferenceCard(title: "Canvas", symbol: "rectangle.on.rectangle") {
                        Picker("Canvas", selection: $canvas) {
                            Text("Midnight").tag("midnight")
                            Text("Graphite").tag("graphite")
                            Text("Ocean").tag("ocean")
                        }.pickerStyle(.segmented)
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12).fill(Color.cineNexAccent.gradient).frame(width: 62, height: 92)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your next obsession").font(.headline)
                                Text("A quieter canvas. A stronger accent.").font(.caption).foregroundStyle(.secondary)
                                Label("Watch tonight", systemImage: "play.fill").font(.caption.bold()).foregroundStyle(Color.cineNexAccent)
                            }
                        }
                    }
                    CineNexPreferenceCard(title: "Accent", symbol: "circle.lefthalf.filled") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 18) {
                            ForEach(accents, id: \.self) { value in
                                Button { accent = value } label: {
                                    VStack(spacing: 8) {
                                        Circle().fill(accentColor(value)).frame(width: 40, height: 40)
                                            .overlay { if accent == value { Image(systemName: "checkmark").bold().foregroundStyle(.black) } }
                                        Text(value.capitalized).font(.caption).foregroundStyle(.primary)
                                    }.frame(maxWidth: .infinity)
                                }.buttonStyle(.plain)
                                .accessibilityAddTraits(accent == value ? .isSelected : [])
                            }
                        }
                    }
                    CineNexPreferenceCard(title: "Presentation", symbol: "square.grid.2x2") {
                        Picker("Poster density", selection: $density) {
                            Text("Comfortable").tag("comfortable")
                            Text("Compact").tag("compact")
                        }.pickerStyle(.segmented)
                        Toggle("Show ratings on posters", isOn: $showRatings)
                        Toggle("Reduce decorative motion", isOn: $reduceMotion)
                        Text("System Reduce Motion is also respected. Video playback continues normally.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .background(Color.cineNexBackground.ignoresSafeArea())
            .navigationTitle("Studio").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .tint(Color.cineNexAccent)
        }.preferredColorScheme(.dark)
    }
    private func accentColor(_ value: String) -> Color {
        switch value {
        case "blue": return Color(red: 0.24, green: 0.52, blue: 1)
        case "rose": return Color(red: 0.95, green: 0.32, blue: 0.58)
        case "teal": return Color(red: 0.12, green: 0.72, blue: 0.68)
        case "amber": return Color(red: 1, green: 0.62, blue: 0.22)
        case "lime": return Color(red: 0.65, green: 0.85, blue: 0.24)
        default: return Color(red: 0.64, green: 0.49, blue: 1)
        }
    }
}
