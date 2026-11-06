import AppKit
import SwiftUI

/// The rounded island grows from the notch and shrinks before the panel hides.
struct IslandBannerView: View {
    @ObservedObject var presenter: BannerPresenter
    @ObservedObject var glm: GLMUsageStore
    @ObservedObject var codex: CodexUsageStore
    private let islandWidth: CGFloat = 360
    private let contentHeight: CGFloat = 52
    private let islandHeight: CGFloat = 174

    var body: some View {
        ZStack(alignment: .top) {
            surface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var surface: some View {
        let expanded = presenter.state == .full
        VStack(spacing: 0) {
            // Keep the real notch line clear so the surface reads as growing out of it.
            Color.clear.frame(height: presenter.note == nil ? 54 : 34)
            if let note = presenter.note {
                bannerContent(note)
                    .frame(width: islandWidth - 32, height: contentHeight)
                    .opacity(expanded ? 1 : 0)
            } else if expanded {
                usageContent
                    .frame(width: islandWidth - 80, height: islandHeight - 74)
                    .transition(.opacity)
            }
        }
        .frame(width: presenter.state.width, height: presenter.state.height, alignment: .top)
        .overlay(alignment: .top) {
            Button(action: presenter.expandFromView) {
                HStack(spacing: 0) {
                    minimalProvider(icon: "codex", name: "Codex", value: codex.error == nil ? codex.fiveHourRemaining : nil)
                    Spacer(minLength: 185)
                    minimalProvider(icon: "zai", name: "GLM", value: glm.error == nil ? glm.fiveHourRemainingPercent : nil)
                }
                .frame(width: islandWidth - 40, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show agent usage details")
            .opacity(presenter.state == .minimal ? 1 : 0)
            .allowsHitTesting(presenter.state == .minimal)
            .accessibilityHidden(presenter.state != .minimal)
            .frame(width: presenter.state.width, height: 32)
            .clipped()
        }
        .background {
            let shape = IslandShape(radius: expanded ? 34 : 16)
            if presenter.look != .systemExperimental {
                ZStack {
                    shape.fill(.black)
                        .shadow(color: .black.opacity(expanded ? 0.25 : 0), radius: 12, y: 12)
                    shape.fill(.black)
                        .shadow(color: .black.opacity(expanded ? 0.25 : 0), radius: 5, y: 4)
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
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
            case .systemExperimental:
                PrivateGlassBackdrop()
            }
            if presenter.look != .solid {
                shape.fill(.black)
                    .opacity(presenter.expandPreference == .minimal && !expanded ? 1 : 0)
            }
            shape.strokeBorder(.white.opacity(expanded ? (presenter.look == .glassy ? 0.25 : 0.12) : 0), lineWidth: 0.8)
        }
    }

    private func minimalProvider(icon: String, name: String, value: Double?) -> some View {
        HStack(spacing: 4) {
            ProviderIcon(name: icon, size: 14)
            Text(percentage(value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), 5 hour remaining \(percentage(value))")
    }

    private var usageContent: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .top, spacing: 14) {
                providerColumn(name: "Codex", icon: "codex",
                               value: codex.error == nil ? codex.fiveHourRemaining : nil,
                               reset: codex.error == nil ? codex.primaryResetAt : nil,
                               weekly: codex.error == nil ? codex.secondaryRemaining : nil,
                               weeklyReset: codex.error == nil ? codex.secondaryResetAt : nil,
                               status: codex.error ?? (codex.signInState == .signingIn ? "Signing in…" : "Sign in via menu"),
                               showWeekly: true, now: context.date)
                Rectangle().fill(.white.opacity(0.16)).frame(width: 1)
                providerColumn(name: "GLM", icon: "zai",
                               value: glm.error == nil ? glm.fiveHourRemainingPercent : nil,
                               reset: glm.error == nil ? glm.fiveHourResetAt : nil,
                               weekly: nil, weeklyReset: nil,
                               status: glm.error ?? (glm.hasKey ? "Loading…" : "Set API key via menu"),
                               showWeekly: false, now: context.date)
            }
            .foregroundStyle(.white)
            .monospacedDigit()
            .preferredColorScheme(.dark)
        }
    }

    private func providerColumn(name: String, icon: String, value: Double?, reset: Date?, weekly: Double?, weeklyReset: Date?, status: String, showWeekly: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProviderIcon(name: icon)
                Text(name.uppercased())
                    .font(.custom("JetBrainsMono-Regular", size: 9).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            HStack(alignment: .center) {
                Text(value.map(percentage) ?? "—")
                    .font(.custom("JetBrainsMono-Regular", size: 18).weight(.semibold))
                Spacer(minLength: 2)
                if let value {
                    ZStack {
                        Circle().stroke(.white.opacity(0.17), lineWidth: 3)
                        Circle().trim(from: 0, to: min(1, max(0, value / 100)))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                }
            }
            HStack(spacing: 3) {
                if value == nil {
                    Text(status).lineLimit(1).truncationMode(.tail)
                } else {
                    Text("5h")
                    if let reset, let countdown = ResetCountdown.text(until: reset, now: now) {
                        Text("· ↻ \(countdown)")
                    }
                }
            }
            .font(.custom("JetBrainsMono-Regular", size: 9))
            .foregroundStyle(.white.opacity(0.7))
            if showWeekly {
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
                HStack(spacing: 4) {
                    Text("1w")
                    Text(percentage(weekly))
                    if let weeklyReset, let countdown = ResetCountdown.text(until: weeklyReset, now: now), weekly != nil {
                        Text(countdown).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .help(value == nil ? status : "\(name): remaining usage")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), 5 hour remaining \(percentage(value))\(showWeekly ? ", 1 week remaining \(percentage(weekly))" : "")")
    }

    private func percentage(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
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

private struct ProviderIcon: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: "circle.dashed").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
