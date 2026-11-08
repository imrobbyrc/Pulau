import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case island, notifications, agents, piSubagents
    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: return "Island"
        case .notifications: return "Notifications"
        case .agents: return "Agents"
        case .piSubagents: return "Pi Subagents"
        }
    }

    var icon: String {
        switch self {
        case .island: return "windshield.wave.and.drop"
        case .notifications: return "bell"
        case .agents: return "cpu"
        case .piSubagents: return "puzzle.piece"
        }
    }
}

/// Dedicated settings window: dark chrome with a section sidebar; each pane is a glass
/// card whose shape belongs to this caller (standard rounded corners, not notch styling).
struct SettingsView: View {
    @ObservedObject var notifications: NotificationWatcher
    @ObservedObject var glm: GLMUsageStore
    @ObservedObject var codex: CodexUsageStore
    @ObservedObject var rex: RexAgentStore
    @ObservedObject var piPlugin: PiPluginManager
    @State private var section: SettingsSection = .island
    @State private var buddyEpoch = UUID()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Design.spacingS) {
                Text("PULAU SETTINGS")
                    .font(.mono(10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, Design.spacingL)
                    .padding(.top, Design.spacingXL)
                    .padding(.bottom, Design.spacingM)
                ForEach(SettingsSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: Design.spacingS) {
                            Image(systemName: item.icon).frame(width: 16)
                            Text(item.title)
                            Spacer(minLength: 0)
                        }
                        .font(.mono(12, weight: section == item ? .semibold : .regular))
                        .foregroundStyle(section == item ? .white : .white.opacity(0.65))
                        .padding(.horizontal, Design.spacingM)
                        .padding(.vertical, 6)
                        .background(section == item ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Design.spacingS)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 172)
            Rectangle().fill(.white.opacity(Design.hairline)).frame(width: 1)
            ScrollView {
                selectedSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.spacingL)
                    .background {
                        GlassSurface(look: notifications.look,
                                     shape: RoundedRectangle(cornerRadius: Design.cornerCard, style: .continuous),
                                     glassTint: notifications.look == .glassy ? .black.opacity(0.5) : nil,
                                     blackFill: notifications.look == .glassy ? 0.35 : nil)
                        RoundedRectangle(cornerRadius: Design.cornerCard, style: .continuous)
                            .strokeBorder(.white.opacity(Design.strokeBright), lineWidth: 0.8)
                    }
            }
            .padding(Design.spacingL)
        }
        .frame(width: 660, height: 520)
        .background(.black)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch section {
        case .island: islandSection
        case .notifications: notificationsSection
        case .agents: agentsSection
        case .piSubagents: piPluginSection
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.mono(10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(Design.hairline)).frame(height: 1)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.spacingS) {
            header(title)
            content()
        }
    }

    // MARK: Island

    private var islandSection: some View {
        VStack(alignment: .leading, spacing: Design.spacingM) {
            group("Island look") {
                GlassSegmentedPicker(options: [
                    (IslandLook.glassy, "Glassy"),
                    (IslandLook.solid, "Solid"),
                    (IslandLook.systemExperimental, "System"),
                ], selection: $notifications.look)
            }
            divider
            group("Expand size") {
                GlassSegmentedPicker(options: [
                    (ExpandPreference.default, "Default"),
                    (ExpandPreference.minimal, "Minimal"),
                ], selection: $notifications.expandPreference)
            }
            Text("The look applies to the island, hover panels, and this window's glass card.")
                .font(.mono(9))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: Design.spacingM) {
            group("Capture") {
                HStack {
                    Text("Notifications").font(.mono(11))
                    Spacer(minLength: 0)
                    GlassToggle(isOn: Binding(
                        get: { notifications.isListening },
                        set: { $0 ? notifications.start() : notifications.stop() }
                    ), label: "Notifications")
                }
                Text(notifications.status)
                    .font(.mono(10))
                    .foregroundStyle(.white.opacity(Design.textSecondary))
            }
            divider
            group("Test") {
                rowButton("Test banner (visual only)") { notifications.showTestBanner() }
                rowButton("Test usage alert") { notifications.showTestQuotaAlert() }
            }
            divider
            group("Permissions") {
                rowButton("Full Disk Access Settings…") { notifications.openPrivacySettings() }
                Text("Pulau reads notification content. Full Disk Access required.")
                    .font(.mono(9))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: Agents

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: Design.spacingM) {
            group("Usage") {
                usageLine("GLM 5h", glm.fiveHourRemainingPercent, glm.hasKey ? nil : "Set GLM API key")
                if glm.hasKey {
                    usageLine("Weekly", glm.weeklyRemainingPercent, nil)
                }
                usageLine("Codex 5h", codex.signInState == .signedIn ? codex.fiveHourRemaining : nil,
                          codex.signInState == .signedIn ? nil : "Sign in to Codex")
                HStack(spacing: Design.spacingL) {
                    if glm.hasKey {
                        rowButton("GLM: refresh") { glm.refreshNow() }
                        rowButton("Set key…") { setGLMKey() }
                        rowButton("Remove key") { glm.removeKey() }
                    } else {
                        rowButton("Set GLM API key…") { setGLMKey() }
                    }
                    if codex.signInState == .signedIn {
                        rowButton("Codex: refresh") { codex.refreshNow() }
                        rowButton("Sign out") { codex.signOut() }
                    } else if codex.signInState == .signingIn {
                        rowButton("Cancel Codex sign-in") { codex.signOut() }
                    } else {
                        rowButton("Sign in to Codex…") { codex.signIn() }
                    }
                }
                if let error = glm.error { Text(error).font(.mono(9)).foregroundStyle(.white.opacity(0.6)) }
                if let error = codex.error { Text(error).font(.mono(9)).foregroundStyle(.white.opacity(0.6)) }
            }
            divider
            group("Usage alerts") {
                Text("A liquid circle detaches from the island when a 5h limit crosses a threshold.")
                    .font(.mono(9))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                rowButton("Test usage alert") { notifications.showTestQuotaAlert() }
            }
            divider
            group("Working buddy") {
                Text(rex.snapshot.summary)
                    .font(.mono(10))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                buddyGroup
            }
            divider
            agentAwakeGroup
        }
    }

    private var buddyGroup: some View {
        let custom = notifications.buddyStore
        return HStack(spacing: Design.spacingM) {
            // buddyEpoch bumps so the preview re-reads the store after adopt/reset.
            Group {
                if let image = custom.resolve() {
                    BuddyAssetView(image: image, animate: true)
                        .frame(width: 32, height: 32)
                } else {
                    AgentEyes(animate: true).frame(width: 32, height: 16)
                }
            }
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
            rowButton(custom.usesCustom ? "Change image…" : "Choose image/GIF…") { chooseBuddy() }
            if custom.usesCustom {
                rowButton("Use built-in eyes") { custom.reset() }
            }
            if let name = custom.usesCustom ? custom.assetName : nil {
                Text(name).font(.mono(9)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
        }
        .id(buddyEpoch)
    }

    private func chooseBuddy() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image or animated GIF for the working buddy"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try notifications.buddyStore.adopt(url)
            buddyEpoch = UUID()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private var agentAwakeGroup: some View {
        group("Agent awake") {
            HStack {
                Text("Keep awake while agents work").font(.mono(11))
                Spacer(minLength: 0)
                GlassToggle(isOn: Binding(
                    get: { notifications.sleepGuard.isEnabled },
                    set: { notifications.sleepGuard.isEnabled = $0 }
                ), label: "Keep awake while agents work")
            }
            HStack {
                Text("Sleep after idle").font(.mono(11))
                Spacer(minLength: 0)
                GlassSegmentedPicker(options: [(1, "1m"), (2, "2m"), (5, "5m")], selection: Binding(
                    get: { notifications.sleepGuard.idleMinutes },
                    set: { notifications.sleepGuard.idleMinutes = $0 }
                ))
                .disabled(!notifications.sleepGuard.isEnabled)
            }
            Text(notifications.sleepGuard.isEnabled
                    ? (notifications.sleepPreventing ? "Keeping Mac awake" : "Sleep allowed")
                    : "Off")
                .font(.mono(10))
                .foregroundStyle(.white.opacity(Design.textSecondary))
        }
    }

    // MARK: Pi Subagents

    private var piPluginSection: some View {
        VStack(alignment: .leading, spacing: Design.spacingM) {
            group("Plugin") {
                if piPlugin.busy {
                    Text("Updating Pi plugin…").font(.mono(11))
                } else if let status = piPlugin.status {
                    if status.source != nil {
                        HStack {
                            Text("Enable Pi Subagents").font(.mono(11))
                            Spacer(minLength: 0)
                            GlassToggle(isOn: Binding(
                                get: { piPlugin.status?.enabled ?? false },
                                set: { piPlugin.setEnabled($0) }
                            ), label: "Enable Pi Subagents")
                            .disabled(status.piFiltered || !status.filesAvailable)
                        }
                        if !status.filesAvailable {
                            Text("Plugin files missing; uninstall and reinstall.")
                                .font(.mono(9)).foregroundStyle(.white.opacity(0.55))
                        } else if status.piFiltered {
                            Text("Managed by pi config; change its filter there.")
                                .font(.mono(9)).foregroundStyle(.white.opacity(0.55))
                        }
                        rowButton("Uninstall Pi plugin…") { confirmPiPluginRemoval() }
                    } else {
                        rowButton("Install Pi plugin") { piPlugin.install() }
                    }
                }
            }
            divider
            group("Notes") {
                Text("Session /pulau-subagents off still applies. Older Pi sessions may need /reload after subagents finish.")
                    .font(.mono(9))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let message = piPlugin.message {
                    Text(message).font(.mono(9)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .onAppear { piPlugin.refresh() }
    }

    private func usageLine(_ label: String, _ percent: Double?, _ fallback: String?) -> some View {
        Group {
            if let percent {
                Text("\(label): \(Int(percent.rounded()))% left").font(.mono(11))
            } else {
                Text(fallback ?? "\(label): unavailable")
                    .font(.mono(11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.mono(11))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
    }

    private func confirmPiPluginRemoval() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Pi Subagents plugin?"
        alert.informativeText = "This disables reporting and removes the plugin registration from Pi. Existing Pi sessions may need /reload after active subagents finish. Pi data will not be deleted."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { piPlugin.uninstall() }
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

/// Minimal menu-bar menu: settings entry point plus quit.
struct PulauMenuContent: View {
    @ObservedObject var notifications: NotificationWatcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: "pulau-settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Pulau") { NSApplication.shared.terminate(nil) }
    }
}
