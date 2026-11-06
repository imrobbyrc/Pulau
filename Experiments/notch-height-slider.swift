import AppKit
import QuartzCore
import ObjectiveC

final class Flipped: NSView { override var isFlipped: Bool { true } }

final class BlackOverlay: NSView {
    override var isFlipped: Bool { true }
    var shape: CGPath?
    var bandHeight: CGFloat = 14
    var darkness: CGFloat = 1
    var fadeLength: CGFloat = 70
    var levels: [CGFloat] = [0.8, 0.5, 0.2]

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let shape else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(shape)
        context.clip()
        context.setFillColor(NSColor.black.withAlphaComponent(darkness).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bandHeight))
        let alphas = [darkness] + levels.map { $0 * darkness } + [0]
        let colors = alphas.map { NSColor.black.withAlphaComponent($0).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 0.5, 0.75, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bandHeight), end: CGPoint(x: 0, y: bandHeight + fadeLength), options: [])
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var controls: NSWindow!
    var glass: NSGlassEffectView!
    var valueLabel: NSTextField!
    var highlightLabel: NSTextField!
    var highlight: Double = 0.13
    var bandHeight: CGFloat = 30
    var darkness: CGFloat = 1
    var blackOverlay: BlackOverlay!
    var previewRoot: Flipped!
    var previewText: NSTextField!
    var islandHeightLabel: NSTextField!
    var fadeSlider: NSSlider!
    var fadeRatio: CGFloat = 140.0 / 160.0
    var heightLabel: NSTextField!
    var darknessLabel: NSTextField!
    var fadeLabel: NSTextField!
    var levelLabels: [NSTextField] = []
    let width: CGFloat = 400
    var height: CGFloat = 80

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel = NSPanel(contentRect: NSRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        assert(Self.scaledFade(140, oldHeight: 160, newHeight: 80) == 70)
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: height))
        previewRoot = root
        root.wantsLayer = true
        panel.contentView = root

        glass = NSGlassEffectView(frame: root.bounds)
        glass.style = .regular
        glass.cornerRadius = 34
        glass.wantsLayer = true
        root.addSubview(glass)
        setGlassPath()
        setVariant(11)

        let shape = islandPath()
        assert(shape.contains(CGPoint(x: width / 2, y: 1)))
        assert(!shape.contains(CGPoint(x: 0, y: 10)))
        blackOverlay = BlackOverlay(frame: root.bounds)
        blackOverlay.shape = shape
        blackOverlay.bandHeight = bandHeight
        blackOverlay.darkness = darkness
        blackOverlay.fadeLength = 70
        blackOverlay.wantsLayer = true
        blackOverlay.layer?.zPosition = 10
        root.addSubview(blackOverlay)
        previewText = NSTextField(labelWithString: "Codex  5h 81%       GLM  5h 95%")
        previewText.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        previewText.textColor = .white
        previewText.frame = NSRect(x: 42, y: 39, width: 330, height: 22)
        previewText.wantsLayer = true
        previewText.layer?.zPosition = 20
        root.addSubview(previewText)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.applyHighlight() }

        controls = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 685), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controls.title = "Pulau — Island Height Tester"
        controls.level = .floating
        controls.center()
        let islandSlider = NSSlider(value: 80, minValue: 80, maxValue: 160, target: self, action: #selector(islandHeightChanged(_:)))
        islandSlider.frame = NSRect(x: 24, y: 598, width: 390, height: 25)
        controls.contentView?.addSubview(islandSlider)
        islandHeightLabel = NSTextField(labelWithString: "Island height: 80 pt (50%)")
        islandHeightLabel.frame = NSRect(x: 24, y: 635, width: 390, height: 22)
        controls.contentView?.addSubview(islandHeightLabel)
        let slider = NSSlider(value: 11, minValue: 0, maxValue: 19, target: self, action: #selector(sliderChanged(_:)))
        slider.numberOfTickMarks = 20
        slider.allowsTickMarkValuesOnly = true
        slider.frame = NSRect(x: 24, y: 528, width: 390, height: 25)
        controls.contentView?.addSubview(slider)
        valueLabel = NSTextField(labelWithString: "Variant: 11")
        valueLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        valueLabel.frame = NSRect(x: 24, y: 565, width: 390, height: 22)
        controls.contentView?.addSubview(valueLabel)
        let highlightSlider = NSSlider(value: highlight, minValue: 0, maxValue: 1, target: self, action: #selector(highlightChanged(_:)))
        highlightSlider.frame = NSRect(x: 24, y: 455, width: 390, height: 25)
        controls.contentView?.addSubview(highlightSlider)
        highlightLabel = NSTextField(labelWithString: "Highlight: 13%")
        highlightLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        highlightLabel.frame = NSRect(x: 24, y: 485, width: 390, height: 22)
        controls.contentView?.addSubview(highlightLabel)
        let heightSlider = NSSlider(value: 30, minValue: 0, maxValue: 100, target: self, action: #selector(bandHeightChanged(_:)))
        heightSlider.frame = NSRect(x: 24, y: 378, width: 390, height: 25)
        controls.contentView?.addSubview(heightSlider)
        heightLabel = NSTextField(labelWithString: "Black band height: 30 pt")
        heightLabel.frame = NSRect(x: 24, y: 408, width: 390, height: 22)
        controls.contentView?.addSubview(heightLabel)
        let darknessSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: self, action: #selector(darknessChanged(_:)))
        darknessSlider.frame = NSRect(x: 24, y: 305, width: 390, height: 25)
        controls.contentView?.addSubview(darknessSlider)
        darknessLabel = NSTextField(labelWithString: "Black band opacity: 100%")
        darknessLabel.frame = NSRect(x: 24, y: 335, width: 390, height: 22)
        controls.contentView?.addSubview(darknessLabel)
        fadeSlider = NSSlider(value: 70, minValue: 10, maxValue: 140, target: self, action: #selector(fadeChanged(_:)))
        fadeSlider.frame = NSRect(x: 24, y: 235, width: 390, height: 25)
        controls.contentView?.addSubview(fadeSlider)
        fadeLabel = NSTextField(labelWithString: "Fade length: 70 pt")
        fadeLabel.frame = NSRect(x: 24, y: 265, width: 390, height: 22)
        controls.contentView?.addSubview(fadeLabel)
        for index in 0..<3 {
            let y = CGFloat(165 - index * 70)
            let label = NSTextField(labelWithString: "Fade level \(index + 1): \(Int(blackOverlay.levels[index] * 100))%")
            label.frame = NSRect(x: 24, y: y + 30, width: 390, height: 22)
            controls.contentView?.addSubview(label)
            levelLabels.append(label)
            let levelSlider = NSSlider(value: Double(blackOverlay.levels[index]), minValue: 0, maxValue: 1, target: self, action: #selector(levelChanged(_:)))
            levelSlider.tag = index
            levelSlider.frame = NSRect(x: 24, y: y, width: 390, height: 25)
            controls.contentView?.addSubview(levelSlider)
        }
        controls.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("Prototype ready: variant slider 0-19")
        fflush(stdout)
    }

    static func scaledFade(_ fade: CGFloat, oldHeight: CGFloat, newHeight: CGFloat) -> CGFloat {
        fade * newHeight / oldHeight
    }

    @objc func islandHeightChanged(_ slider: NSSlider) {
        let newHeight = CGFloat(slider.doubleValue.rounded())
        let frame = panel.frame
        height = newHeight
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
        previewRoot.frame = NSRect(x: 0, y: 0, width: width, height: height)
        glass.frame = previewRoot.bounds
        blackOverlay.frame = previewRoot.bounds
        blackOverlay.shape = islandPath()
        blackOverlay.fadeLength = min(140, max(10, (height * fadeRatio).rounded()))
        blackOverlay.needsDisplay = true
        previewText.frame = NSRect(x: 42, y: max(34, height * 0.38), width: 330, height: 22)
        setGlassPath()
        fadeSlider.doubleValue = Double(blackOverlay.fadeLength)
        fadeLabel.stringValue = "Fade length: \(Int(blackOverlay.fadeLength)) pt"
        islandHeightLabel.stringValue = "Island height: \(Int(height)) pt (\(Int(height / 160 * 100))%)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.applyHighlight() }
        print("island height=\(Int(height)), fade=\(Int(blackOverlay.fadeLength))")
        fflush(stdout)
    }

    @objc func fadeChanged(_ slider: NSSlider) {
        blackOverlay.fadeLength = CGFloat(slider.doubleValue.rounded())
        fadeRatio = blackOverlay.fadeLength / height
        fadeLabel.stringValue = "Fade length: \(Int(blackOverlay.fadeLength)) pt"
        blackOverlay.needsDisplay = true
    }

    @objc func levelChanged(_ slider: NSSlider) {
        let index = slider.tag
        guard blackOverlay.levels.indices.contains(index) else { return }
        blackOverlay.levels[index] = CGFloat(slider.doubleValue)
        levelLabels[index].stringValue = "Fade level \(index + 1): \(Int((slider.doubleValue * 100).rounded()))%"
        blackOverlay.needsDisplay = true
    }

    @objc func bandHeightChanged(_ slider: NSSlider) {
        bandHeight = CGFloat(slider.doubleValue.rounded())
        heightLabel.stringValue = "Black band height: \(Int(bandHeight)) pt"
        updateBand()
    }

    @objc func darknessChanged(_ slider: NSSlider) {
        darkness = CGFloat(slider.doubleValue)
        darknessLabel.stringValue = "Black band opacity: \(Int((darkness * 100).rounded()))%"
        updateBand()
    }

    func updateBand() {
        blackOverlay.bandHeight = bandHeight
        blackOverlay.darkness = darkness
        blackOverlay.needsDisplay = true
        print("black band height=\(Int(bandHeight)) opacity=\(Int((darkness * 100).rounded()))%")
        fflush(stdout)
    }

    @objc func sliderChanged(_ slider: NSSlider) {
        let value = slider.integerValue
        setVariant(value)
        valueLabel.stringValue = "Variant: \(value)"
    }

    @objc func highlightChanged(_ slider: NSSlider) {
        highlight = slider.doubleValue
        highlightLabel.stringValue = "Highlight: \(Int(highlight * 100))%"
        applyHighlight()
    }

    func applyHighlight() {
        guard let root = glass.layer else { print("glass layer unavailable"); fflush(stdout); return }
        var count = 0
        func visit(_ layer: CALayer) {
            if layer.responds(to: NSSelectorFromString("effect")),
               layer.responds(to: NSSelectorFromString("setEffect:")),
               let effect = layer.value(forKey: "effect") as? NSObject,
               NSStringFromClass(type(of: effect)) == "CASDFKeyFillHighlightEffect",
               effect.responds(to: NSSelectorFromString("setKeyAmount:")),
               effect.responds(to: NSSelectorFromString("setFillAmount:")),
               let copy = effect.copy() as? NSObject {
                copy.setValue(highlight, forKey: "keyAmount")
                copy.setValue(highlight, forKey: "fillAmount")
                layer.setValue(copy, forKey: "effect")
                print("highlight key=\(copy.value(forKey: "keyAmount") ?? "?") fill=\(copy.value(forKey: "fillAmount") ?? "?")")
                count += 1
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
        if count == 0 { print("highlight effect unavailable") }
        fflush(stdout)
    }

    func setVariant(_ value: Int) {
        guard glass.responds(to: NSSelectorFromString("set_variant:")) else {
            print("Variant setter unavailable"); fflush(stdout); return
        }
        glass.setValue(value, forKey: "_variant")
        setGlassPath()
        print("variant=\(value)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.applyHighlight() }
        fflush(stdout)
    }

    func setGlassPath() {
        let selector = NSSelectorFromString("_setPath:")
        guard glass.responds(to: selector),
              let method = class_getInstanceMethod(NSGlassEffectView.self, selector),
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding) == "v24@0:8r^{CGPath=}16" else {
            print("Private path signature unsupported; native rounded glass fallback")
            fflush(stdout)
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, CGPath) -> Void
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        var flip = CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
        guard let glassPath = islandPath().copy(using: &flip) else {
            print("Unable to flip notch path; using native rounded glass")
            return
        }
        setter(glass, selector, glassPath)
        print("Custom notch path passed to private glass setter (glass coordinates)")
        fflush(stdout)
    }

    func islandPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addCurve(to: CGPoint(x: width - 20, y: 18), control1: CGPoint(x: width - 11, y: 0), control2: CGPoint(x: width - 20, y: 8))
        path.addLine(to: CGPoint(x: width - 20, y: height - 34))
        path.addQuadCurve(to: CGPoint(x: width - 54, y: height), control: CGPoint(x: width - 20, y: height))
        path.addLine(to: CGPoint(x: 54, y: height))
        path.addQuadCurve(to: CGPoint(x: 20, y: height - 34), control: CGPoint(x: 20, y: height))
        path.addLine(to: CGPoint(x: 20, y: 18))
        path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: 20, y: 8), control2: CGPoint(x: 11, y: 0))
        path.closeSubpath()
        return path
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
