import AppKit
import SwiftUI

@main
struct PulauApp: App {
    @StateObject private var notifications: NotificationWatcher
    @StateObject private var glm: GLMUsageStore
    @StateObject private var codex: CodexUsageStore
    @StateObject private var rex: RexAgentStore
    @StateObject private var piPlugin = PiPluginManager()

    /// SwiftUI can construct the App struct more than once; shared stores keep a
    /// single NotificationWatcher (and a single island panel) alive.
    @MainActor
    private enum SharedStores {
        static let glm = GLMUsageStore()
        static let codex = CodexUsageStore()
        static let rex = RexAgentStore()
        static let notifications = NotificationWatcher(glm: glm, codex: codex, rex: rex)
    }

    init() {
        _glm = StateObject(wrappedValue: SharedStores.glm)
        _codex = StateObject(wrappedValue: SharedStores.codex)
        _rex = StateObject(wrappedValue: SharedStores.rex)
        _notifications = StateObject(wrappedValue: SharedStores.notifications)
        Self.startE2EShotsIfRequested()
        Self.startE2EHoverIfRequested(notifications: SharedStores.notifications)
        Self.startE2EExpandIfRequested(notifications: SharedStores.notifications)
    }

    var body: some Scene {
        MenuBarExtra("Pulau", systemImage: "bell.badge") {
            PulauMenuContent(notifications: notifications)
        }
        Window("Pulau Settings", id: "pulau-settings") {
            SettingsView(notifications: notifications, glm: glm, codex: codex, rex: rex, piPlugin: piPlugin)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    /// Test hook: `--e2e-shots <dir>` renders every visible app window to that
    /// directory, so E2E can verify UI without Screen Recording permission.
    @MainActor
    private static func startE2EShotsIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--e2e-shots"), arguments.indices.contains(index + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let cgWindows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as NSArray?) as? [[CFString: Any]] ?? []
                for (number, window) in NSApplication.shared.windows.enumerated() where window.isVisible {
                    guard let view = window.contentView else { continue }
                    let bounds = view.bounds
                    guard bounds.width > 1, bounds.height > 1 else { continue }
                    let kind = window is NSPanel ? "panel" : "window"
                    if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
                        view.cacheDisplay(in: bounds, to: rep)
                        if let data = rep.representation(using: .png, properties: [:]) {
                            try? data.write(to: directory.appendingPathComponent("\(number)-\(kind).png"))
                        }
                    }
                    // Live WindowServer composite: includes Liquid Glass that cacheDisplay misses.
                    // The island panel is the widest visible Pulau window.
                    let panelEntry = cgWindows.compactMap { entry -> (area: Double, number: NSNumber)? in
                        guard (entry[kCGWindowOwnerName as CFString] as? String) == "Pulau",
                              let b = (entry[kCGWindowBounds as CFString] as? NSDictionary) as? [String: NSNumber] else { return nil }
                        let area = (b["Width"]?.doubleValue ?? 0) * (b["Height"]?.doubleValue ?? 0)
                        guard area > 100_000 else { return nil }
                        guard let n = entry[kCGWindowNumber as CFString] as? NSNumber else { return nil }
                        return (area, n)
                    }.max { $0.area < $1.area }
                    try? "\(cgWindows.count) cg \(panelEntry?.area ?? -1)".write(to: directory.appendingPathComponent("live-debug.txt"), atomically: true, encoding: .utf8)
                    if let windowNumber = panelEntry?.number,
                       let live = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(windowNumber.uint32Value), [.bestResolution]) {
                        let liveRep = NSBitmapImageRep(cgImage: live)
                        if let liveData = liveRep.representation(using: .png, properties: [:]) {
                            try? liveData.write(to: directory.appendingPathComponent("\(number)-live.png"))
                        }
                    }
                }
            }
        }
    }

    /// Test hook: `--e2e-hover` opens the agent detail panel after launch, so E2E can
    /// capture it without synthesizing mouse events.
    @MainActor
    private static func startE2EHoverIfRequested(notifications: NotificationWatcher) {
        guard ProcessInfo.processInfo.arguments.contains("--e2e-hover") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            notifications.presenter.agentDetailHovered = true
        }
    }

    /// Test hook: `--e2e-expand` expands the usage island after launch.
    @MainActor
    private static func startE2EExpandIfRequested(notifications: NotificationWatcher) {
        guard ProcessInfo.processInfo.arguments.contains("--e2e-expand") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            notifications.presenter.expandFromView()
        }
    }
}
