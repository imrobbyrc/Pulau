import AppKit
import SwiftUI

@main
struct PulauApp: App {
    @StateObject private var notifications = NotificationWatcher()

    var body: some Scene {
        MenuBarExtra("Pulau", systemImage: "bell.badge") {
            Button(notifications.isListening ? "Stop notifications" : "Start notifications") {
                notifications.isListening ? notifications.stop() : notifications.start()
            }
            Text(notifications.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Test banner (visual only)") { notifications.showTestBanner() }
            Divider()
            Button("Full Disk Access Settings…") { notifications.openPrivacySettings() }
            Text("Pulau reads notification content. Full Disk Access required.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit Pulau") { NSApplication.shared.terminate(nil) }
        }
    }
}
