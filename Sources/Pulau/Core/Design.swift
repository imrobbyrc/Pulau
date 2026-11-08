import SwiftUI

/// Shared island design tokens: one place for type, spacing, radii and opacity.
/// Callers compose from these instead of hardcoding values.
enum Design {
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 20
    /// Panels that float (hover panel, windows).
    static let cornerPanel: CGFloat = 22
    /// Cards inset inside a larger surface.
    static let cornerCard: CGFloat = 12
    static let hairline: Double = 0.16
    static let strokeBright: Double = 0.25
    static let textSecondary: Double = 0.62
}

/// The JetBrains Mono face used across the island UI.
extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrainsMono-Regular", size: size).weight(weight)
    }
}

/// The island's three-look material, reusable anywhere: the caller owns the shape,
/// tint strength, and optional tails/dimming, so a card can share the look without
/// inheriting notch styling.
struct GlassSurface<S: Shape>: View {
    let look: IslandLook
    let shape: S
    var glassTint: Color?
    var blackFill: Double?
    var tailX: CGFloat?
    var dimOverlay = false

    var body: some View {
        switch look {
        case .solid:
            shape.fill(.black)
        case .glassy:
            Group {
                if #available(macOS 26.0, *) {
                    if let glassTint {
                        Color.clear.glassEffect(.regular.tint(glassTint), in: shape)
                    } else {
                        Color.clear.glassEffect(.regular.interactive(), in: shape)
                    }
                } else {
                    IslandGlass().clipShape(shape)
                }
                if let blackFill { shape.fill(.black.opacity(blackFill)) }
            }
        case .systemExperimental:
            PrivateGlassBackdrop(tailX: tailX, dim: dimOverlay)
        }
    }
}
