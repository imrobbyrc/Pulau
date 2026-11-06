import AppKit
import SwiftUI

/// The rounded island grows from the notch and shrinks before the panel hides.
struct IslandBannerView: View {
    @ObservedObject var presenter: BannerPresenter
    private let notchWidth: CGFloat = 185
    private let notchHeight: CGFloat = 32
    private let islandWidth: CGFloat = 400
    private let contentHeight: CGFloat = 60
    private let islandHeight: CGFloat = 104

    var body: some View {
        ZStack(alignment: .top) {
            if presenter.note != nil {
                surface
                    .id(presenter.generation)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var surface: some View {
        let expanded = presenter.expanded
        VStack(spacing: 0) {
            // Keep the real notch line clear so the surface reads as growing out of it.
            Color.clear.frame(height: 16)
            if let note = presenter.note {
                bannerContent(note)
                    .frame(width: islandWidth - 32, height: contentHeight)
                    .opacity(expanded ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .frame(width: expanded ? islandWidth + 40 : notchWidth + 40,
               height: expanded ? islandHeight : notchHeight, alignment: .top)
        .background {
            let shape = IslandShape(radius: expanded ? 34 : 16)
            ZStack {
                shape.fill(.black)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 12)
                shape.fill(.black)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
                shape.blendMode(.destinationOut)
            }
            .compositingGroup()
            switch presenter.look {
            case .glassy:
                if #available(macOS 26.0, *) {
                    // Native Liquid Glass material, lightly black-tinted, clipped to the island.
                    Color.clear.glassEffect(.regular.interactive(), in: shape)
                } else {
                    IslandGlass().clipShape(shape)
                }
                // Opaque through the notch band, then a seamless fade into the
                // native glass below — multi-stop S-curve so the transition
                // reads organic, not boxy.
                shape.fill(.black)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.31),
                                .init(color: .black.opacity(0.9), location: 0.4),
                                .init(color: .black.opacity(0.62), location: 0.5),
                                .init(color: .black.opacity(0.32), location: 0.6),
                                .init(color: .black.opacity(0.12), location: 0.7),
                                .init(color: .black.opacity(0), location: 0.8),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            case .solid:
                shape.fill(.black)
            }
            shape.strokeBorder(.white.opacity(presenter.look == .glassy ? 0.25 : 0.12), lineWidth: 0.8)
        }
        .overlay {
            if presenter.look == .glassy, expanded {
                EdgeGlow(shape: IslandShape(radius: 34))
            }
        }
        .onAppear { presenter.expandFromView() }
    }

    private func bannerContent(_ notification: PulauNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.app)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
        .preferredColorScheme(.dark)
    }
}

/// iOS 27-style semi glass black: Liquid Glass tinted dark on macOS 26+,
/// HUD material fallback below.
struct IslandGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.tintColor = NSColor.black.withAlphaComponent(0.2)
            glass.cornerRadius = 0
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        return material
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// A top-edge bridge with concave shoulders and continuous-looking lower corners.
struct IslandShape: InsettableShape {
    var radius: CGFloat
    var insetAmount: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, insetAmount) }
        set { radius = newValue.first; insetAmount = newValue.second }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let flare: CGFloat = 20
        let shoulder: CGFloat = 18
        let left = rect.minX + flare, right = rect.maxX - flare
        let r = min(radius, (rect.height - shoulder) / 2, (right - left) / 2)
        let k: CGFloat = 0.55228475
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
                   control1: CGPoint(x: rect.maxX - flare * k, y: rect.minY),
                   control2: CGPoint(x: right, y: rect.minY + shoulder * (1 - k)))
        p.addLine(to: CGPoint(x: right, y: rect.maxY - r))
        p.addCurve(to: CGPoint(x: right - r, y: rect.maxY),
                   control1: CGPoint(x: right, y: rect.maxY - r * (1 - k)),
                   control2: CGPoint(x: right - r * (1 - k), y: rect.maxY))
        p.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        p.addCurve(to: CGPoint(x: left, y: rect.maxY - r),
                   control1: CGPoint(x: left + r * (1 - k), y: rect.maxY),
                   control2: CGPoint(x: left, y: rect.maxY - r * (1 - k)))
        p.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                   control1: CGPoint(x: left, y: rect.minY + shoulder * (1 - k)),
                   control2: CGPoint(x: rect.minX + flare * k, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Siri-style animated edge glow: a slowly rotating conic gradient stroked
/// around the island silhouette, breathing opacity, with a blurred inner
/// emission for bloom. Static under Reduce Motion. Technique adapted from
/// AkashKundu03/SwiftUI-BreathingScreen (MIT).
struct EdgeGlow: View {
    let shape: IslandShape
    var breathePeriod: Double = 5
    var rotationPeriod: Double = 9

    private static let stops: [Gradient.Stop] = [
        .init(color: Color(red: 0.78, green: 0.53, blue: 1.0), location: 0.0),
        .init(color: Color(red: 0.55, green: 0.6, blue: 1.0), location: 0.3),
        .init(color: Color(red: 0.96, green: 0.73, blue: 0.92), location: 0.45),
        .init(color: Color(red: 1.0, green: 0.4, blue: 0.47), location: 0.62),
        .init(color: Color(red: 1.0, green: 0.73, blue: 0.44), location: 0.75),
        .init(color: Color(red: 0.78, green: 0.53, blue: 1.0), location: 1.0),
    ]

    var body: some View {
        if Motion.reduce {
            coreStroke(gradient: AngularGradient(gradient: Gradient(stops: Self.stops), center: .center))
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = 0.5 + 0.5 * sin(2 * .pi * (t / breathePeriod))
                let angle = (t.truncatingRemainder(dividingBy: rotationPeriod) / rotationPeriod) * 360
                coreStroke(
                    gradient: AngularGradient(
                        gradient: Gradient(stops: Self.stops),
                        center: .center,
                        angle: .degrees(angle)
                    )
                )
                .opacity(0.35 + 0.3 * phase)
            }
        }
    }

    private func coreStroke(gradient: AngularGradient) -> some View {
        let core = shape.inset(by: 1).stroke(gradient, lineWidth: 2)
        let inner = shape
            .inset(by: 2)
            .stroke(gradient, lineWidth: 8)
            .blur(radius: 7)
            .blendMode(.plusLighter)
            .clipShape(shape.inset(by: 2))
        return ZStack { core; inner }
            .compositingGroup()
            .allowsHitTesting(false)
    }
}
