import SwiftUI

extension Color {
    static var cineNexBackground: Color {
        switch UserDefaults.standard.string(forKey: "cinenex.canvasStyle") ?? "midnight" {
        case "graphite": return Color(red: 0.065, green: 0.065, blue: 0.07)
        case "ocean": return Color(red: 0.025, green: 0.065, blue: 0.09)
        default: return Color(red: 0.025, green: 0.027, blue: 0.045)
        }
    }
    static var cineNexSurface: Color {
        switch UserDefaults.standard.string(forKey: "cinenex.canvasStyle") ?? "midnight" {
        case "graphite": return Color(red: 0.12, green: 0.12, blue: 0.13)
        case "ocean": return Color(red: 0.055, green: 0.12, blue: 0.15)
        default: return Color(red: 0.075, green: 0.08, blue: 0.12)
        }
    }
    static var cineNexAccent: Color {
        switch UserDefaults.standard.string(forKey: "cinenex.accentPreset") ?? "amber" {
        case "blue": return Color(red: 0.24, green: 0.52, blue: 1)
        case "rose": return Color(red: 0.95, green: 0.32, blue: 0.58)
        case "teal": return Color(red: 0.12, green: 0.72, blue: 0.68)
        case "amber": return Color(red: 1, green: 0.67, blue: 0.30)
        case "lime": return Color(red: 0.65, green: 0.85, blue: 0.24)
        case "violet": return Color(red: 0.64, green: 0.49, blue: 1)
        default: return Color(red: 1, green: 0.67, blue: 0.30)
        }
    }
}

struct CineNexPreferenceCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Color.cineNexAccent)
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cineNexSurface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.06)) }
    }
}
