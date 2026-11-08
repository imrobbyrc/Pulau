import AppKit
import SwiftUI

@MainActor
final class Playback: ObservableObject {
    @Published private(set) var start = Date.now
    @Published private(set) var from = 0.0
    @Published private(set) var target = 0.0
    @Published var liquidHeight = 31.0
    @Published var breakPercent = 87.0
    @Published var pinchPercent = 61.0
    static let duration = 2.0

    func value(at date: Date) -> Double {
        let t = min(1, max(0, date.timeIntervalSince(start) / Self.duration))
        return from + (target - from) * t
    }

    func set(_ split: Bool) {
        let now = Date.now
        from = value(at: now)
        start = now
        target = split ? 1 : 0
    }

    static func spread(_ progress: Double) -> Double {
        let t = min(1, max(0, (progress - 0.12) / 0.88))
        return t * t * (3 - 2 * t)
    }
}

struct LiquidPreview: View {
    @ObservedObject var playback: Playback
    var notchOverlay = false
    var notchWidth: CGFloat = 185
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let center: CGFloat = 220
    private let diameter: CGFloat = 23.04
    private var edge: CGFloat { center + notchWidth / 2 }
    private var restingX: CGFloat { edge - 20 + diameter / 2 + (55.5 - diameter / 2) * 0.7 }

    private var notch: Path {
        let left = center - notchWidth / 2
        let right = center + notchWidth / 2
        let flare: CGFloat = 20, shoulder: CGFloat = 18, radius: CGFloat = 7
        let k: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: right, y: 0))
        path.addCurve(to: CGPoint(x: right - flare, y: shoulder),
                      control1: CGPoint(x: right - flare * k, y: 0),
                      control2: CGPoint(x: right - flare, y: shoulder * (1 - k)))
        path.addLine(to: CGPoint(x: right - flare, y: 32 - radius))
        path.addCurve(to: CGPoint(x: right - flare - radius, y: 32),
                      control1: CGPoint(x: right - flare, y: 32 - radius * (1 - k)),
                      control2: CGPoint(x: right - flare - radius * (1 - k), y: 32))
        path.addLine(to: CGPoint(x: left + flare + radius, y: 32))
        path.addCurve(to: CGPoint(x: left + flare, y: 32 - radius),
                      control1: CGPoint(x: left + flare + radius * (1 - k), y: 32),
                      control2: CGPoint(x: left + flare, y: 32 - radius * (1 - k)))
        path.addLine(to: CGPoint(x: left + flare, y: shoulder))
        path.addCurve(to: CGPoint(x: left, y: 0),
                      control1: CGPoint(x: left + flare, y: shoulder * (1 - k)),
                      control2: CGPoint(x: left + flare * k, y: 0))
        path.closeSubpath()
        return path
    }

    var outsideNotch: Path {
        var mask = Path(CGRect(x: 0, y: 0, width: 440, height: 72))
        mask.addPath(notch)
        return mask
    }

    func liquidBridge(circleX: CGFloat) -> Path {
        let start = edge - 20
        let end = circleX - diameter / 2 + 7
        let gap = end - start
        let finalGap = restingX - diameter / 2 + 7 - start
        let breakGap = finalGap * playback.breakPercent / 100
        let pinchStart = breakGap * playback.pinchPercent / 100
        guard gap > 0, gap < breakGap else { return Path() }
        let t = min(1, max(0, (gap - pinchStart) / (breakGap - pinchStart)))
        let pinch = 1 - t * t * (3 - 2 * t)
        let halfBase = playback.liquidHeight / 2 * pinch
        let halfNeck = min(diameter / 2 - 0.5, 10 * playback.liquidHeight / 31) * pinch
        var path = Path()
        path.move(to: CGPoint(x: start, y: 16 - halfBase))
        path.addCurve(to: CGPoint(x: end, y: 16 - halfNeck),
                      control1: CGPoint(x: start + gap * 0.4, y: 16 - halfBase),
                      control2: CGPoint(x: end - gap * 0.35, y: 16 - halfNeck))
        path.addLine(to: CGPoint(x: end, y: 16 + halfNeck))
        path.addCurve(to: CGPoint(x: start, y: 16 + halfBase),
                      control1: CGPoint(x: end - gap * 0.35, y: 16 + halfNeck),
                      control2: CGPoint(x: start + gap * 0.4, y: 16 + halfBase))
        path.closeSubpath()
        return path
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = playback.value(at: timeline.date)
            let spread = Playback.spread(progress)
            let origin = edge - 20 - diameter / 2
            let x = origin + (restingX - origin) * spread
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    if !notchOverlay { context.fill(notch, with: .color(.black)) }
                    context.clip(to: outsideNotch, style: FillStyle(eoFill: true))
                    if reduceMotion {
                        var circle = context
                        circle.opacity = progress
                        circle.fill(Path(ellipseIn: CGRect(x: restingX - diameter / 2, y: (32 - diameter) / 2, width: diameter, height: diameter)), with: .color(.black))
                    } else if progress > 0 {
                        context.fill(liquidBridge(circleX: x), with: .color(.black))
                        context.fill(Path(ellipseIn: CGRect(x: x - diameter / 2, y: (32 - diameter) / 2, width: diameter, height: diameter)), with: .color(.black))
                    }
                }
                VStack(spacing: 0) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .bold))
                    Text("30%").font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .offset(x: (reduceMotion ? restingX : x) - diameter / 2, y: (32 - diameter) / 2)
                .opacity(min(1, max(0, (spread - 0.8) / 0.15)))
            }
            .frame(width: 440, height: 72)
            .allowsHitTesting(false)
        }
        .frame(width: 440, height: 72)
        .accessibilityLabel("Preview alert GLM, 30 percent remaining")
    }
}

struct Controls: View {
    @ObservedObject var playback: Playback
    let notchWidth: CGFloat
    var body: some View {
        VStack(spacing: 16) {
            Text("Liquid Split — Prototype")
                .font(.title2.weight(.semibold))
            Text("Preview di notch dan di bawah. Tidak mengubah Pulau.")
                .foregroundStyle(.secondary)
            LiquidPreview(playback: playback, notchWidth: notchWidth)
                .background(Color(nsColor: .systemGray).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                Button("Split") { playback.set(true) }
                Button("Merge") { playback.set(false) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ukuran sambungan: \(Int(playback.liquidHeight)) pt")
                    .font(.caption.monospacedDigit())
                Slider(value: $playback.liquidHeight, in: 16...60, step: 1)
                    .accessibilityLabel("Ukuran sambungan liquid")
                Text("Titik putus: \(Int(playback.breakPercent))% jarak akhir")
                    .font(.caption.monospacedDigit())
                Slider(value: $playback.breakPercent, in: 35...98, step: 1)
                    .accessibilityLabel("Titik putus liquid")
                Text("Mulai menipis: \(Int(playback.pinchPercent))% menuju titik putus")
                    .font(.caption.monospacedDigit())
                Slider(value: $playback.pinchPercent, in: 0...95, step: 1)
                    .accessibilityLabel("Mulai menipis")
            }
            Text("Tutup jendela ini untuk keluar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 500)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let playback = Playback()
    private var panel: NSPanel?
    private var controls: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        assert(Playback.spread(0) == 0 && abs(Playback.spread(0.56) - 0.5) < 0.001 && Playback.spread(1) == 1)
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = right.minX - left.maxX
        } else {
            notchWidth = 185
        }
        let preview = LiquidPreview(playback: playback, notchWidth: notchWidth)
        let mask = preview.outsideNotch
        let notchEdge = 220 + notchWidth / 2
        assert(preview.liquidBridge(circleX: notchEdge - 20).isEmpty)
        let initialHeight = preview.liquidBridge(circleX: notchEdge + 5).boundingRect.height
        assert(initialHeight > 28)
        playback.liquidHeight = 50
        assert(preview.liquidBridge(circleX: notchEdge + 5).boundingRect.height > initialHeight)
        playback.liquidHeight = 31
        playback.breakPercent = 35
        assert(preview.liquidBridge(circleX: notchEdge + 5).isEmpty)
        playback.breakPercent = 87
        assert(preview.liquidBridge(circleX: notchEdge + 50).isEmpty)
        assert(!mask.contains(CGPoint(x: 220, y: 16), eoFill: true))
        assert(mask.contains(CGPoint(x: 220, y: 40), eoFill: true))
        assert(mask.contains(CGPoint(x: 220 + notchWidth / 2 - 5, y: 28), eoFill: true))
        assert(mask.contains(CGPoint(x: 220 - notchWidth / 2 + 5, y: 28), eoFill: true))
        let panel = NSPanel(contentRect: NSRect(x: screen.frame.midX - 220, y: screen.frame.maxY - 72, width: 440, height: 72), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: LiquidPreview(playback: playback, notchOverlay: true, notchWidth: notchWidth))
        panel.orderFrontRegardless()
        self.panel = panel

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pulau — Liquid Split Prototype"
        window.delegate = self
        window.contentView = NSHostingView(rootView: Controls(playback: playback, notchWidth: notchWidth))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.controls = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Delegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}
