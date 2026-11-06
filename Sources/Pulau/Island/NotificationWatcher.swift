import AppKit
import SwiftUI

@MainActor
final class NotificationWatcher: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var status = "Off"

    private let capture = NotificationCapture()
    private var timer: Timer?
    private let presenter = BannerPresenter()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Active island look; persisted so the choice survives relaunch.
    /// Published so the menu checkmark follows immediately.
    @Published var look: IslandLook = UserDefaults.standard.string(forKey: "islandLook").flatMap(IslandLook.init(rawValue:)) ?? .glassy {
        didSet {
            presenter.look = look
            UserDefaults.standard.set(look.rawValue, forKey: "islandLook")
        }
    }
    // Debug: swap the island for an unconditional red rect to isolate
    // panel+hosting rendering from view logic.
    private let plainRect = ProcessInfo.processInfo.arguments.contains("--plain")

    init() {
        presenter.look = look
        // Debug affordance: run the binary with --test-banner to flash a
        // banner and quit, so capture can be checked without UI scripting.
        if ProcessInfo.processInfo.arguments.contains("--test-banner") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showTestBanner() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { NSApplication.shared.terminate(nil) }
        }
        // Renders the banner view to /tmp/pulau_banner.png without needing
        // Screen Recording permission, to prove what the hosting view draws.
        if ProcessInfo.processInfo.arguments.contains("--snapshot-banner") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showTestBanner() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.snapshotAndQuit() }
        }
    }

    private func snapshotAndQuit() {
        defer { NSApplication.shared.terminate(nil) }
        guard let view = panel?.contentView else { NSLog("SNAPSHOT no contentView"); return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSLog("SNAPSHOT no rep"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let bytes = rep.bitmapData {
            let bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
            var transparent = 0, partial = 0, opaque = 0, total = 0
            let alphaIndex = spp - 1
            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            for y in stride(from: 0, to: height, by: 4) {
                for x in stride(from: 0, to: width, by: 4) {
                    let offset = y * bpr + x * spp + alphaIndex
                    let alpha = bytes[offset]
                    total += 1
                    if alpha == 0 { transparent += 1 } else if alpha == 255 { opaque += 1 } else { partial += 1 }
                }
            }
            NSLog("SNAPSHOT alpha total=\(total) transparent=\(transparent) partial=\(partial) opaque=\(opaque)")
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { NSLog("SNAPSHOT encode failed"); return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/pulau_banner.png"))
        NSLog("SNAPSHOT written bytes=\(data.count) bounds=\(view.bounds)")
    }


    func start() {
        guard !isListening else { return }
        isListening = true
        capture.start()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        isListening = false
        timer?.invalidate()
        timer = nil
        dismissTask?.cancel()
        presenter.dismiss()
        panel?.contentViewController = nil
        panel?.orderOut(nil)
        capture.stop()
        status = "Off"
    }

    func showTestBanner() {
        show(PulauNotification(app: "Pulau", title: "Test notification", body: "Pulau banner is working."))
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private func poll() {
        guard isListening else { return }
        capture.poll { show($0) }
        status = capture.status
    }

    private func show(_ notification: PulauNotification) {
        let width: CGFloat = 440
        let height: CGFloat = 190
        let panel = panel ?? makePanel(width: width, height: height)
        self.panel = panel
        if panel.contentViewController == nil {
            let controller = NSHostingController(rootView: plainRect
                ? AnyView(Rectangle().fill(.red).frame(width: 440, height: 160))
                : AnyView(IslandBannerView(presenter: presenter).frame(width: width, height: height, alignment: .top)))
            controller.sizingOptions = []
            panel.contentViewController = controller
            panel.setContentSize(NSSize(width: width, height: height))
        }
        if let screen = NSScreen.main {
            // The fixed-size panel stays pinned while only its contents animate.
            panel.setFrameTopLeftPoint(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.maxY))
        }
        panel.orderFrontRegardless()
        presenter.present(notification)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let duration = Motion.dismissDuration
            self.presenter.dismiss(duration: duration)
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.panel?.contentViewController = nil
            self.presenter.clear()
        }
    }

    private func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

