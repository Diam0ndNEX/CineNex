import SwiftUI

/// Keep Liquid Glass on controls, with opaque accessibility and iOS 18 fallbacks.
private struct CineNexGlassControl<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.black.opacity(0.88), in: shape)
                .overlay { shape.stroke(.white.opacity(0.18), lineWidth: 1) }
        } else if #available(iOS 26, *) {
            content.glassEffect(
                .regular.tint(prominent ? .white.opacity(0.18) : .clear).interactive(interactive),
                in: shape
            )
        } else {
            content.background(.thinMaterial, in: shape)
                .overlay { shape.stroke(.white.opacity(0.12), lineWidth: 1) }
        }
    }
}

extension View {
    /// System buttons get the native treatment without putting glass behind whole content cards.
    @ViewBuilder
    func cineNexGlassButtons() -> some View {
        if #available(iOS 26, *) { self.buttonStyle(.glass) }
        else { self.buttonStyle(.bordered) }
    }

    func cineNexGlass<S: Shape>(in shape: S, interactive: Bool = true, prominent: Bool = false) -> some View {
        modifier(CineNexGlassControl(shape: shape, interactive: interactive, prominent: prominent))
    }
}

/// Nearby controls share a glass sampling region. Separate control groups stay independent.
struct CineNexGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    @ViewBuilder var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
