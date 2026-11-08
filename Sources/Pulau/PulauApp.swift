import AppKit
import SwiftUI

@main
struct PulauApp: App {
    @StateObject private var notifications: NotificationWatcher
    @StateObject private var glm: GLMUsageStore
    @StateObject private var codex: CodexUsageStore
    @StateObject private var rex: RexAgentStore
    @StateObject private var piPlugin = PiPluginManager()

    init() {
        let store = GLMUsageStore()
        let codexStore = CodexUsageStore()
        let rexStore = RexAgentStore()
        _glm = StateObject(wrappedValue: store)
        _codex = StateObject(wrappedValue: codexStore)
        _rex = StateObject(wrappedValue: rexStore)
        _notifications = StateObject(wrappedValue: NotificationWatcher(glm: store, codex: codexStore, rex: rexStore))
        Self.startE2EShotsIfRequested()
        Self.startE2EHoverIfRequested(notifications: _notifications.wrappedValue)
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
            for (number, window) in NSApplication.shared.windows.enumerated() where window.isVisible {
                guard let view = window.contentView else { continue }
                let bounds = view.bounds
                guard bounds.width > 1, bounds.height > 1,
                      let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
                view.cacheDisplay(in: bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let kind = window is NSPanel ? "panel" : "window"
                try? data.write(to: directory.appendingPathComponent("\(number)-\(kind).png"))
            }
            }
        }
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
}
