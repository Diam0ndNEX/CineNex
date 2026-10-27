import SwiftUI

struct AppearanceSettingsView: View {
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
    @AppStorage("cinenex.home.featuredCount") private var featuredCount = 5
    @AppStorage("cinenex.home.shelfLayout") private var shelfLayout = "posters"
    @AppStorage("cinenex.home.continueLayout") private var continueLayout = "cards"
    @AppStorage("cinenex.detailActionPlacement") private var detailActionPlacement = "inline"
    @AppStorage("cinenex.navigationHaptics") private var navigationHaptics = true
    private let accents = ["amber", "blue", "rose", "teal", "violet", "lime"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CineNexPreferenceCard(title: "Color & canvas", symbol: "paintpalette") {
                    Picker("Canvas", selection: $canvas) {
                        Text("Black").tag("midnight")
                        Text("Graphite").tag("graphite")
                        Text("Ocean").tag("ocean")
                        Text("OLED").tag("oled")
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
                    Toggle("Navigation haptics", isOn: $navigationHaptics)
                    Text("The floating navigation dock uses Liquid Glass, with an opaque Reduce Transparency fallback. Changing the launch screen applies the next time CineNex starts.").font(.caption).foregroundStyle(.secondary)
                }
                CineNexPreferenceCard(title: "Your Home", symbol: "house") {
                    Toggle("Featured spotlight", isOn: $showFeatured)
                    if showFeatured {
                        Picker("Spotlight layout", selection: $featuredStyle) {
                            Text("Edge to edge").tag("fullBleed")
                            Text("Artwork card").tag("immersive")
                            Text("Compact").tag("compact")
                        }.pickerStyle(.segmented)
                        Picker("Featured titles", selection: $featuredCount) {
                            ForEach([3, 5, 7], id: \.self) { Text("\($0) titles").tag($0) }
                        }
                        Toggle("Spotlight story preview", isOn: $featuredSynopsis)
                        Text("Swipe or use the arrows to change the featured title. No automatic carousel or video playback runs in the background.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Toggle("Continue watching", isOn: $showContinue)
                    if showContinue {
                        Picker("Resume layout", selection: $continueLayout) {
                            Text("Wide cards").tag("cards")
                            Text("Compact rows").tag("rows")
                        }.pickerStyle(.segmented)
                    }
                    Picker("Catalog shelf artwork", selection: $shelfLayout) {
                        Text("Posters").tag("posters")
                        Text("Landscape crops").tag("landscape")
                    }.pickerStyle(.segmented)
                    Toggle("Saved watchlist shelf", isOn: $showWatchlist)
                    Toggle("Highly rated shelf", isOn: $showRated)
                    Toggle("Genre shortcuts", isOn: $showGenres)
                    Text("Movie and series shelves remain available. Empty shelves are automatically hidden.").font(.caption).foregroundStyle(.secondary)
                }
                CineNexPreferenceCard(title: "Title details", symbol: "info.circle") {
                    Picker("Play & save buttons", selection: $detailActionPlacement) {
                        Text("Below the title").tag("inline")
                        Text("Floating at bottom").tag("pinned")
                    }
                    Text("Keep actions beside the title artwork, or pin them while you scroll through cast and episodes.")
                        .font(.caption).foregroundStyle(.secondary)
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
        .toolbar(.visible, for: .navigationBar)
        .tint(Color.cineNexAccent)
        .preferredColorScheme(.dark)
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
