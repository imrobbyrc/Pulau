import AppKit
import Combine
import SwiftUI

@MainActor
final class NotificationWatcher: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var status = "Off"

    private let capture = NotificationCapture()
    private let preferences: IslandPreferences
    private let quotaThresholds: QuotaThresholdTracker
    private var pendingQuotaAlerts: [QuotaAlert] = []
    private var activeQuotaAlert: QuotaAlert?
    private var timer: Timer?
    let presenter = BannerPresenter()  // internal for the --e2e-hover test hook
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var rexSubscription: AnyCancellable?
    private var rexEventSubscription: AnyCancellable?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let glm: GLMUsageStore
    private let codex: CodexUsageStore
    private let rex: RexAgentStore
    @Published private(set) var sleepPreventing = false
    let sleepGuard: SleepGuard
    let buddyStore: BuddyStore
    private var sleepSubscription: AnyCancellable?
    private var pointerInside = false
    private var notchWidth: CGFloat = 185

    /// Active island look; persisted so the choice survives relaunch.
    /// Published so the menu checkmark follows immediately.
    @Published var look: IslandLook {
        didSet {
            presenter.look = look
            preferences.look = look
        }
    }
    @Published var expandPreference: ExpandPreference {
        didSet {
            presenter.expandPreference = expandPreference
            preferences.expandPreference = expandPreference
            updatePointer()
        }
    }
    // Debug: swap the island for an unconditional red rect to isolate
    // panel+hosting rendering from view logic.
    private let plainRect = ProcessInfo.processInfo.arguments.contains("--plain")

    init(glm: GLMUsageStore, codex: CodexUsageStore, rex: RexAgentStore, defaults: UserDefaults = .standard) {
        self.glm = glm
        self.codex = codex
        self.rex = rex
        let preferences = IslandPreferences(defaults: defaults)
        self.preferences = preferences
        self.quotaThresholds = QuotaThresholdTracker(defaults: defaults)
        self.sleepGuard = SleepGuard(preferences: AgentAwakePreferences(defaults: defaults))
        self.buddyStore = BuddyStore(defaults: defaults)
        self.look = preferences.look
        self.expandPreference = preferences.expandPreference
        sleepSubscription = sleepGuard.$preventingSleep.sink { [weak self] in self?.sleepPreventing = $0 }
        presenter.look = look
        presenter.expandPreference = expandPreference
        glm.onQuotaUpdate = { [weak self] in self?.receiveQuota($0, provider: .glm) }
        codex.onQuotaUpdate = { [weak self] in self?.receiveQuota($0, provider: .codex) }
        glm.onCredentialsChanged = { [weak self] in self?.quotaThresholds.reset(.glm) }
        codex.onCredentialsChanged = { [weak self] in self?.quotaThresholds.reset(.codex) }
        rexSubscription = rex.$snapshot.sink { [weak self] snapshot in
            self?.presenter.updateAgentActivity(snapshot)
            self?.sleepGuard.update(snapshot: snapshot)
        }
        rexEventSubscription = rex.$activityEvent.compactMap { $0 }.sink { [weak self] event in
            self?.presenter.updateAgentActivity(event: event)
        }
        if preferences.notificationsEnabled { start() }
        DispatchQueue.main.async { [weak self] in self?.showIsland() }
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
        preferences.notificationsEnabled = true
        isListening = true
        capture.start()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        preferences.notificationsEnabled = false
        isListening = false
        timer?.invalidate()
        timer = nil
        capture.stop()
        status = "Off"
    }

    func showTestBanner() {
        show(PulauNotification(app: "Pulau", title: "Test notification", body: "Pulau banner is working."))
    }

    func showTestQuotaAlert() {
        enqueueQuotaAlert(QuotaAlert(provider: .glm, remaining: 30))
    }

    private func receiveQuota(_ remaining: Double, provider: QuotaThresholdTracker.Provider) {
        guard quotaThresholds.crossedThreshold(for: provider, remaining: remaining) != nil else { return }
        enqueueQuotaAlert(QuotaAlert(provider: provider, remaining: Int(ceil(remaining))))
    }

    private func enqueueQuotaAlert(_ alert: QuotaAlert) {
        if presenter.note != nil { pendingQuotaAlerts.append(alert) }
        else { showQuotaAlert(alert) }
    }

    private func showQuotaAlert(_ alert: QuotaAlert) {
        let name = alert.provider == .glm ? "GLM" : "Codex"
        let note = PulauNotification(app: name, title: "5h limit: \(alert.remaining)% left", body: "")
        show(note, quotaAlert: alert)
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

    private func showIsland() {
        guard panel == nil else { return }
        let width: CGFloat = 440
        let screen = NSScreen.main
        let height = min(490, max(190, (screen?.visibleFrame.height ?? 530) - 40))
        let notchWidth: CGFloat
        if let left = screen?.auxiliaryTopLeftArea, let right = screen?.auxiliaryTopRightArea,
           right.minX > left.maxX, right.minX - left.maxX < width {
            notchWidth = right.minX - left.maxX
        } else {
            notchWidth = 185
        }
        self.notchWidth = notchWidth
        let panel = makePanel(width: width, height: height)
        self.panel = panel
        let controller = NSHostingController(rootView: plainRect
            ? AnyView(Rectangle().fill(.red).frame(width: 440, height: 160))
            : AnyView(IslandBannerView(presenter: presenter, glm: glm, codex: codex, rex: rex, notchWidth: notchWidth, panelHeight: height, buddyStore: buddyStore).frame(width: width, height: height, alignment: .top)))
        controller.sizingOptions = []
        panel.contentViewController = controller
        panel.setContentSize(NSSize(width: width, height: height))
        if let screen {
            // The fixed-size panel stays pinned while only its contents animate.
            panel.setFrameTopLeftPoint(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.maxY))
        }
        panel.orderFrontRegardless()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.updatePointer() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.updatePointer()
            return event
        }
        updatePointer()
    }

    private func updatePointer() {
        guard let panel else { return }
        let frame = panel.frame
        let width = presenter.quotaAlert == nil ? presenter.state.width : IslandState.collapsed.width
        let height = presenter.quotaAlert == nil ? presenter.state.height : IslandState.collapsed.height
        let rect = NSRect(x: frame.midX - width / 2, y: frame.maxY - height,
                          width: width, height: height).insetBy(dx: -4, dy: -4)
        let point = NSEvent.mouseLocation
        let activityAvailable = presenter.note == nil && presenter.state == .collapsed && presenter.agentActivityVisible && presenter.agentActivity?.stage == .working
        let detailHeight = QuotaLiquidAlert.detailHeight(for: rex.snapshot, available: frame.height - QuotaLiquidAlert.detailY)
        let overActivity = activityAvailable && Self.agentHoverContains(point, frame: frame, notchWidth: notchWidth,
                                                                       includeDetail: presenter.agentDetailHovered, detailHeight: detailHeight)
        if presenter.agentDetailHovered != overActivity {
            withAnimation(Motion.spring) { presenter.agentDetailHovered = overActivity }
        }
        let inside = rect.contains(point) && !overActivity
        panel.ignoresMouseEvents = !inside && !overActivity
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverTask?.cancel()
        if inside {
            presenter.setHovered(true)
        } else {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                self?.presenter.setHovered(false)
            }
        }
    }

    static func agentHoverContains(_ point: NSPoint, frame: NSRect, notchWidth: CGFloat, includeDetail: Bool,
                                   detailHeight: CGFloat) -> Bool {
        let center = frame.minX + QuotaLiquidAlert.restingX(notchWidth: notchWidth)
        let bubble = NSRect(x: center - QuotaLiquidAlert.diameter / 2, y: frame.maxY - 32 + (32 - QuotaLiquidAlert.diameter) / 2,
                            width: QuotaLiquidAlert.diameter, height: QuotaLiquidAlert.diameter).insetBy(dx: -5, dy: -5)
        let detail = NSRect(x: frame.minX + QuotaLiquidAlert.detailX(notchWidth: notchWidth),
                            y: frame.maxY - QuotaLiquidAlert.detailY - detailHeight,
                            width: QuotaLiquidAlert.detailWidth, height: detailHeight + QuotaLiquidAlert.tailHeight)
        return bubble.contains(point) || (includeDetail && detail.contains(point))
    }

    private func show(_ notification: PulauNotification, quotaAlert: QuotaAlert? = nil) {
        if let activeQuotaAlert { pendingQuotaAlerts.insert(activeQuotaAlert, at: 0) }
        activeQuotaAlert = quotaAlert
        showIsland()
        presenter.present(notification, quotaAlert: quotaAlert)
        updatePointer()
        let generation = presenter.generation
        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.presenter, presenter.generation == generation else { return }
            presenter.expandFromView()
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let duration = self.activeQuotaAlert != nil && !Motion.reduce
                ? QuotaLiquidAlert.duration : Motion.dismissDuration
            self.presenter.dismiss(duration: duration)
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.presenter.clear()
            self.activeQuotaAlert = nil
            if !self.pendingQuotaAlerts.isEmpty {
                self.showQuotaAlert(self.pendingQuotaAlerts.removeFirst())
            } else {
                self.updatePointer()
            }
        }
    }

    private func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.ignoresMouseEvents = true
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

