import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinenex.accentPreset") private var accent = "amber"
    @AppStorage("cinenex.canvasStyle") private var canvas = "midnight"
    @AppStorage("cinenex.posterDensity") private var density = "comfortable"
    @AppStorage("cinenex.showRatings") private var showRatings = true
    @AppStorage("cinenex.posterMetadata") private var posterMetadata = true
    @AppStorage("cinenex.reduceMotion") private var reduceMotion = false
    @AppStorage("cinenex.navigationLabels") private var navigationLabels = true
    @AppStorage("cinenex.startTab") private var startTab = "home"
    @AppStorage("cinenex.featuredStyle") private var featuredStyle = "immersive"
    @AppStorage("cinenex.featuredSynopsis") private var featuredSynopsis = true
    @AppStorage("cinenex.home.showFeatured") private var showFeatured = true
    @AppStorage("cinenex.home.showContinue") private var showContinue = true
    @AppStorage("cinenex.home.showWatchlist") private var showWatchlist = true
    @AppStorage("cinenex.home.showRated") private var showRated = true
    @AppStorage("cinenex.home.showGenres") private var showGenres = true
    private let accents = ["amber", "blue", "rose", "teal", "violet", "lime"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Appearance & layout").font(.largeTitle.bold())
                    Text("Choose colors, home sections, and navigation.").font(.subheadline).foregroundStyle(.secondary)
                    CineNexPreferenceCard(title: "Color & canvas", symbol: "paintpalette") {
                        Picker("Canvas", selection: $canvas) {
                            Text("Midnight").tag("midnight")
                            Text("Graphite").tag("graphite")
                            Text("Ocean").tag("ocean")
                        }.pickerStyle(.segmented)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 18) {
                            ForEach(accents, id: \.self) { value in
                                Button { accent = value } label: {
                                    VStack(spacing: 8) {
                                        Circle().fill(accentColor(value)).frame(width: 36, height: 36)
                                            .overlay { if accent == value { Image(systemName: "checkmark").bold().foregroundStyle(.black) } }
                                        Text(value.capitalized).font(.caption).foregroundStyle(.primary)
                                    }.frame(maxWidth: .infinity)
                                }.buttonStyle(.plain)
                                .accessibilityLabel("\(value.capitalized) accent")
                                .accessibilityAddTraits(accent == value ? .isSelected : [])
                            }
                        }
                    }
                    CineNexPreferenceCard(title: "Navigation", symbol: "rectangle.bottomthird.inset.filled") {
                        Picker("Open on launch", selection: $startTab) {
                            Text("Home").tag("home")
                            Text("Discover").tag("browse")
                            Text("Library").tag("library")
                        }
                        Toggle("Navigation button labels", isOn: $navigationLabels)
                        Text("The floating navigation dock uses Liquid Glass, with an opaque Reduce Transparency fallback. Changing the launch screen applies the next time CineNex starts.").font(.caption).foregroundStyle(.secondary)
                    }
                    CineNexPreferenceCard(title: "Your Home", symbol: "house") {
                        Toggle("Featured spotlight", isOn: $showFeatured)
                        if showFeatured {
                            Picker("Spotlight layout", selection: $featuredStyle) {
                                Text("Immersive").tag("immersive")
                                Text("Compact").tag("compact")
                            }.pickerStyle(.segmented)
                            Toggle("Spotlight story preview", isOn: $featuredSynopsis)
                        }
                        Divider()
                        Toggle("Continue watching", isOn: $showContinue)
                        Toggle("Saved watchlist shelf", isOn: $showWatchlist)
                        Toggle("Highly rated shelf", isOn: $showRated)
                        Toggle("Genre shortcuts", isOn: $showGenres)
                        Text("Movie and series shelves remain available. Empty shelves are automatically hidden.").font(.caption).foregroundStyle(.secondary)
                    }
                    CineNexPreferenceCard(title: "Posters & accessibility", symbol: "square.grid.2x2") {
                        Picker("Poster density", selection: $density) {
                            Text("Comfortable").tag("comfortable")
                            Text("Compact").tag("compact")
                        }.pickerStyle(.segmented)
                        Toggle("Poster year & rating labels", isOn: $posterMetadata)
                        Toggle("Show ratings", isOn: $showRatings)
                        Toggle("Reduce decorative motion", isOn: $reduceMotion)
                        Text("System Reduce Motion and Reduce Transparency are also respected. Video playback continues normally.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .background(Color.cineNexBackground.ignoresSafeArea())
            .navigationTitle("Appearance & layout").navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .tint(Color.cineNexAccent)
        }.preferredColorScheme(.dark)
    }
    private func accentColor(_ value: String) -> Color {
        switch value {
        case "blue": return Color(red: 0.24, green: 0.52, blue: 1)
        case "rose": return Color(red: 0.95, green: 0.32, blue: 0.58)
        case "teal": return Color(red: 0.12, green: 0.72, blue: 0.68)
        case "amber": return Color(red: 1, green: 0.67, blue: 0.30)
        case "lime": return Color(red: 0.65, green: 0.85, blue: 0.24)
        default: return Color(red: 0.64, green: 0.49, blue: 1)
        }
    }
}
