import AppKit
import SwiftUI

@main
struct PulauApp: App {
    @StateObject private var notifications = NotificationWatcher()
    @StateObject private var glm = GLMUsageStore()

    var body: some Scene {
        MenuBarExtra("Pulau", systemImage: "bell.badge") {
            Button(notifications.isListening ? "Stop notifications" : "Start notifications") {
                notifications.isListening ? notifications.stop() : notifications.start()
            }
            Button("Test banner (visual only)") { notifications.showTestBanner() }
            Divider()
            Picker("Island Look", selection: Binding(
                get: { notifications.look },
                set: { notifications.look = $0 }
            )) {
                Text("Glassy").tag(IslandLook.glassy)
                Text("Solid").tag(IslandLook.solid)
            }
            .pickerStyle(.inline)
            Text(notifications.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Full Disk Access Settings…") { notifications.openPrivacySettings() }
            Text("Pulau reads notification content. Full Disk Access required.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Section("Agent Usage") {
                if glm.hasKey {
                    if let percent = glm.fiveHourRemainingPercent {
                        Text("GLM 5h: \(Int(percent.rounded()))% left")
                    } else {
                        Text(glm.loading ? "GLM: loading…" : "GLM 5h: unavailable")
                    }
                    if let percent = glm.weeklyRemainingPercent {
                        Text("Weekly: \(Int(percent.rounded()))% left")
                    }
                    if let plan = glm.planName { Text("Plan: \(plan)") }
                    if let error = glm.error { Text(error) }
                    Button("Refresh now") { glm.refreshNow() }
                    Button("Set GLM API key…") { setGLMKey() }
                    Button("Remove GLM API key") { glm.removeKey() }
                } else {
                    Button("GLM: set API key…") { setGLMKey() }
                    if let error = glm.error { Text(error) }
                }
            }
            Divider()
            Button("Quit Pulau") { NSApplication.shared.terminate(nil) }
        }
    }

    private func setGLMKey() {
        let alert = NSAlert()
        alert.messageText = "Set GLM API key"
        alert.informativeText = "Your key is stored in Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn { glm.setKey(field.stringValue) }
    }
}
