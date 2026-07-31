import SwiftUI

/// Liquid Glass chrome, with the pre-macOS 26 appearance as the fallback.
///
/// Apple scopes the material to the *functional* layer — toolbars, floating
/// bars, controls — so the content underneath stays legible and the two layers
/// read as distinct. Content panels keep `cardStyle()`; stacking glass on glass
/// is what the guidance warns against, and so is spreading it over every
/// element on a screen.
///
/// The effects ship in macOS 26. Each helper degrades on its own so call sites
/// never spell out an availability check.
extension View {
    /// Marks a floating, control-layer surface.
    ///
    /// `cornerRadius` is the radius used before macOS 26, and the floor for the
    /// concentric radius the system derives from the enclosing window.
    func glassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }

    /// Fades scrolling content out as it passes under a floating bar instead of
    /// letting it collide with the bar's edge.
    @ViewBuilder
    func softScrollEdge(for edges: Edge.Set) -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(corners: .concentric(minimum: .fixed(cornerRadius))))
        } else {
            content
                .background(AppColors.surfaceCard, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                }
        }
    }
}
