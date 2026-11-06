import AppKit
import SwiftUI
import SQLite3

struct PulauNotification: Equatable {
    let app: String
    let title: String
    let body: String

    static func decode(_ data: Data, app: String) -> PulauNotification? {
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }
        let title = request["titl"] as? String ?? ""
        let body = [request["subt"] as? String, request["body"] as? String]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !title.isEmpty || !body.isEmpty else { return nil }
        return PulauNotification(app: app, title: title, body: body)
    }
}

// Motion tokens modeled on NotchIsland: springy open, quicker close, ease
// instead of spring when Reduce Motion is on.
enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    // Subtle spring: smooth settle, barely any overshoot.
    static var spring: Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.9) }
    // Dismiss: short ease-out so it never drags at the end.
    static var quick: Animation { reduce ? .easeInOut(duration: 0.1) : .easeOut(duration: 0.22) }
}

@MainActor
final class BannerPresenter: ObservableObject {
    @Published private(set) var note: PulauNotification?
    @Published private(set) var expanded = false
    @Published private(set) var generation = UUID()

    func present(_ notification: PulauNotification) {
        note = notification
        expanded = false
        generation = UUID()
    }

    /// Expand from the view's onAppear so the first render is the collapsed
    /// notch and the spring animates from there.
    func expandFromView() {
        guard !expanded else { return }
        withAnimation(Motion.spring) { expanded = true }
    }

    func dismiss() {
        withAnimation(Motion.quick) { expanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.note = nil }
    }
}

@MainActor
final class NotificationWatcher: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var status = "Off"

    private let database = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path
    private var timer: Timer?
    private var startedAt = 0.0
    private var seen: [String: Double] = [:]
    private let presenter = BannerPresenter()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    // Debug: swap the island for an unconditional red rect to isolate
    // panel+hosting rendering from view logic.
    private let plainRect = ProcessInfo.processInfo.arguments.contains("--plain")

    init() {
        // Debug affordance: run the binary with --test-banner to flash a
        // banner and quit, so capture can be checked without UI scripting.
        if ProcessInfo.processInfo.arguments.contains("--test-banner") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showTestBanner() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { NSApplication.shared.terminate(nil) }
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
        startedAt = Date().timeIntervalSinceReferenceDate
        seen.removeAll()
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
        seen.removeAll()
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
        let fd = open(database, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            status = "Grant Full Disk Access, then relaunch Pulau."
            return
        }
        close(fd)

        var db: OpaquePointer?
        guard sqlite3_open_v2(database, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            status = "Cannot open notification store; check Full Disk Access."
            return
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT hex(r.uuid), r.delivered_date, a.identifier, r.data FROM record AS r JOIN app AS a ON a.app_id = r.app_id WHERE r.delivered_date > ? ORDER BY r.delivered_date ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            status = "Notification store unsupported on this macOS version."
            return
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = max(startedAt, Date().timeIntervalSinceReferenceDate - 30)
        sqlite3_bind_double(statement, 1, cutoff)
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let rawID = sqlite3_column_text(statement, 0),
               let rawApp = sqlite3_column_text(statement, 2),
               let bytes = sqlite3_column_blob(statement, 3) {
                let id = String(cString: rawID)
                let deliveredAt = sqlite3_column_double(statement, 1)
                if seen[id] == nil {
                    seen[id] = deliveredAt
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 3)))
                    if let notification = PulauNotification.decode(data, app: String(cString: rawApp)) {
                        show(notification)
                    }
                }
            }
            result = sqlite3_step(statement)
        }
        seen = seen.filter { $0.value > cutoff }
        status = result == SQLITE_DONE ? "Listening for new notifications" : "Read failed; retrying."
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
            panel.contentViewController = controller
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
            self?.presenter.dismiss()
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            self?.panel?.contentViewController = nil
            self?.panel?.orderOut(nil)
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
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

/// The rounded island grows from the notch and shrinks before the panel hides.
struct IslandBannerView: View {
    @ObservedObject var presenter: BannerPresenter
    private let notchWidth: CGFloat = 185
    private let notchHeight: CGFloat = 32
    private let islandWidth: CGFloat = 400
    private let contentHeight: CGFloat = 60
    private let islandHeight: CGFloat = 128

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
        // Top corners stay square so the surface bridges seamlessly into the
        // notch line; the bottom is heavily rounded, per the reference spec.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 36,
            bottomTrailingRadius: 36,
            topTrailingRadius: 0,
            style: .continuous
        )
        VStack(spacing: 0) {
            Color.clear.frame(height: 16)
            if let note = presenter.note {
                bannerContent(note)
                    .frame(width: islandWidth - 32, height: contentHeight)
                    .transition(.opacity)
            }
        }
        .frame(width: expanded ? islandWidth + 40 : notchWidth + 40,
               height: expanded ? islandHeight : notchHeight, alignment: .top)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Color.black.opacity(0.88)
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.8))
        }
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
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
        .preferredColorScheme(.dark)
    }
}
