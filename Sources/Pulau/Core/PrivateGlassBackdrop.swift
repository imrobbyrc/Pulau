import AppKit
import ObjectiveC
import SwiftUI

struct PrivateGlassBackdrop: NSViewRepresentable {
    var rounded = false
    var tailX: CGFloat?
    var dim = false
    func makeNSView(context: Context) -> PrivateGlassContainer {
        let view = PrivateGlassContainer()
        apply(to: view)
        return view
    }
    func updateNSView(_ view: PrivateGlassContainer, context: Context) { apply(to: view) }
    private func apply(to view: PrivateGlassContainer) {
        view.rounded = rounded
        view.tailX = tailX
        view.dim = dim
    }
}

/// Rounded panel with an upward tail, used by the agent hover panel.
struct AgentPanelShape: InsettableShape {
    var tailX: CGFloat
    var tailHeight: CGFloat = 10
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        let body = CGRect(x: rect.minX, y: rect.minY + tailHeight, width: rect.width, height: rect.height - tailHeight)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: 22, height: 22), style: .continuous)
        let tip = CGPoint(x: rect.minX + tailX, y: rect.minY + 1)
        p.move(to: CGPoint(x: tip.x - 9, y: body.minY + 1))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + 9, y: body.minY + 1))
        p.closeSubpath()
        return p
    }
}

final class PrivateGlassContainer: NSView {
    override var isFlipped: Bool { true }
    private var glassView: NSView!
    private var blackOverlay: PrivateGlassBlackOverlay!
    private var previousSize = NSSize.zero
    var rounded = false { didSet { if rounded != oldValue { previousSize = .zero; needsLayout = true } } }
    var tailX: CGFloat? { didSet { if tailX != oldValue { previousSize = .zero; needsLayout = true } } }
    var dim = false { didSet { if dim != oldValue { blackOverlay.dim = dim; blackOverlay.needsDisplay = true } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if #available(macOS 26.0, *), Self.supportsPrivateGlass(version),
           let glass = Self.makePrivateGlass() {
            glassView = glass
            addSubview(glass)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak glass] in
                if let glass { Self.reduceHighlight(glass) }
            }
        } else {
            let fallback = SystemBackdrop.makeBackdrop()
            glassView = fallback
            addSubview(fallback)
        }
        blackOverlay = PrivateGlassBlackOverlay()
        blackOverlay.wantsLayer = true
        blackOverlay.dim = dim
        addSubview(blackOverlay)
    }

    required init?(coder: NSCoder) { nil }

    static func supportsPrivateGlass(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion == 27 && version.minorVersion == 0 && version.patchVersion == 1
    }

    @available(macOS 26.0, *)
    private static func makePrivateGlass() -> NSGlassEffectView? {
        let glass = NSGlassEffectView()
        let variant = NSSelectorFromString("set_variant:")
        let path = NSSelectorFromString("_setPath:")
        guard glass.responds(to: variant), glass.responds(to: path),
              let method = class_getInstanceMethod(NSGlassEffectView.self, path),
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding) == "v24@0:8r^{CGPath=}16" else { return nil }
        glass.style = .regular
        glass.setValue(11, forKey: "_variant")
        glass.wantsLayer = true
        return glass
    }

    private var pathTimer: Timer?

    override func layout() {
        super.layout()
        guard bounds.size != previousSize, bounds.width > 40, bounds.height > 0 else { return }
        previousSize = bounds.size
        glassView.frame = bounds
        blackOverlay.frame = bounds
        let shape: CGPath
        if let tailX {
            shape = AgentPanelShape(tailX: tailX).path(in: bounds).cgPath
        } else if rounded {
            shape = RoundedRectangle(cornerRadius: 22, style: .continuous).path(in: bounds).cgPath
        } else {
            shape = IslandShape(radius: bounds.height > 32 ? 34 : 16).path(in: bounds).cgPath
        }
        blackOverlay.shape = shape
        blackOverlay.needsDisplay = true
        scheduleGlassUpdate()
    }

    private func currentGlassPath() -> CGPath {
        let bounds = self.bounds
        if let tailX {
            return AgentPanelShape(tailX: tailX).path(in: bounds).cgPath
        }
        if rounded {
            return RoundedRectangle(cornerRadius: 22, style: .continuous).path(in: bounds).cgPath
        }
        return IslandShape(radius: bounds.height > 32 ? 34 : 16).path(in: bounds).cgPath
    }

    /// The variant 11 glass breaks when its path is rewritten every animation
    /// frame, so updates wait for the bounds to settle (~90ms) before applying.
    private func scheduleGlassUpdate() {
        pathTimer?.invalidate()
        let captured = bounds.size
        let timer = Timer(timeInterval: 0.09, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.bounds.size == captured {
                    self.applyGlassPath()
                } else {
                    self.scheduleGlassUpdate()
                }
            }
        }
        pathTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func applyGlassPath() {
        let shape = currentGlassPath()
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            let selector = NSSelectorFromString("_setPath:")
            if let method = class_getInstanceMethod(NSGlassEffectView.self, selector),
               let encoding = method_getTypeEncoding(method),
               String(cString: encoding) == "v24@0:8r^{CGPath=}16" {
                var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
                if let path = shape.copy(using: &flip) {
                    typealias Setter = @convention(c) (AnyObject, Selector, CGPath) -> Void
                    let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
                    setter(glass, selector, path)
                }
            }
        } else {
            let mask = CAShapeLayer()
            mask.frame = bounds
            mask.path = shape
            glassView.wantsLayer = true
            glassView.layer?.mask = mask
        }
    }

    private static func reduceHighlight(_ glass: NSView) {
        guard let root = glass.layer else { return }
        func visit(_ layer: CALayer) {
            if layer.responds(to: NSSelectorFromString("effect")),
               layer.responds(to: NSSelectorFromString("setEffect:")),
               let effect = layer.value(forKey: "effect") as? NSObject,
               NSStringFromClass(type(of: effect)) == "CASDFKeyFillHighlightEffect",
               effect.responds(to: NSSelectorFromString("setKeyAmount:")),
               effect.responds(to: NSSelectorFromString("setFillAmount:")),
               let copy = effect.copy() as? NSObject {
                copy.setValue(0.13, forKey: "keyAmount")
                copy.setValue(0.13, forKey: "fillAmount")
                layer.setValue(copy, forKey: "effect")
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
    }
}

final class PrivateGlassBlackOverlay: NSView {
    override var isFlipped: Bool { true }
    var shape: CGPath?
    var dim = false

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let shape else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(shape)
        context.clip()
        if dim {
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)
            return
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 30))
        let colors = [1.0, 0.8, 0.5, 0.2, 0.0].map { NSColor.black.withAlphaComponent($0).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 0.5, 0.75, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 30), end: CGPoint(x: 0, y: 30 + bounds.height * 140 / 160), options: [])
        }
    }
}
