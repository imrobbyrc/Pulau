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
