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

struct SettingsSectionHistory {
    private(set) var sections: [SettingsSection] = [.island]
    private(set) var index = 0

    var current: SettingsSection { sections[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < sections.count }

    mutating func select(_ section: SettingsSection) {
        guard section != current else { return }
        sections = Array(sections.prefix(index + 1))
        sections.append(section)
        index += 1
    }

    mutating func goBack() {
        if canGoBack { index -= 1 }
    }

    mutating func goForward() {
        if canGoForward { index += 1 }
    }
}

/// Dedicated settings window with searchable sidebar navigation and grouped detail panes.
struct SettingsView: View {
    @ObservedObject var notifications: NotificationWatcher
    @ObservedObject var glm: GLMUsageStore
    @ObservedObject var codex: CodexUsageStore
    @ObservedObject var rex: RexAgentStore
    @ObservedObject var piPlugin: PiPluginManager
    @State private var navigation = SettingsSectionHistory()
    @State private var searchText = ""
    @State private var buddyEpoch = UUID()
    private var section: SettingsSection { navigation.current }

    private var filteredSections: [SettingsSection] {
        guard !searchText.isEmpty else { return SettingsSection.allCases }
        return SettingsSection.allCases.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Search Settings", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 28)

                VStack(spacing: 4) {
                    ForEach(filteredSections) { item in
                        Button { select(item) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(section == item ? Color(red: 0.72, green: 0.86, blue: 0.74) : .white.opacity(0.7))
                                    .frame(width: 27, height: 27)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                                        .foregroundStyle(.white.opacity(section == item ? 0.96 : 0.75))
                                    if section == item {
                                        Text(sectionSubtitle(item))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: section == item ? 56 : 42, alignment: .leading)
                            .background(section == item ? .white.opacity(0.075) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 190)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    HStack(spacing: 0) {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .frame(width: 38, height: 36)
                        }
                        .disabled(!navigation.canGoBack)
                        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 24)
                        Button(action: goForward) {
                            Image(systemName: "chevron.right")
                                .frame(width: 38, height: 36)
                        }
                        .disabled(!navigation.canGoForward)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                    .background(.white.opacity(0.075), in: Capsule())
                    Text(section.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 25)
                .padding(.bottom, 22)

                ScrollView {
                    if filteredSections.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        selectedSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .frame(width: 760, height: 600)
        .background(Color(red: 0.055, green: 0.075, blue: 0.064))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    private func select(_ item: SettingsSection) { navigation.select(item) }
    private func goBack() { navigation.goBack() }
    private func goForward() { navigation.goForward() }

    private func sectionSubtitle(_ item: SettingsSection) -> String {
        switch item {
        case .island:
            switch notifications.look {
            case .glassy: return "Glassy"
            case .solid: return "Solid"
            case .systemExperimental: return "System"
            }
        case .notifications: return notifications.isListening ? "Running" : "Off"
        case .agents: return "GLM · Codex · Rex"
        case .piSubagents: return piPlugin.busy ? "Updating" : (piPlugin.status?.enabled == true ? "Enabled" : "Not installed")
        }
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
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.84))
    }

    private var divider: some View {
        Color.clear.frame(height: 4)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.spacingM) {
            header(title)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape.fill(.white.opacity(0.045))
            shape.strokeBorder(.white.opacity(0.055), lineWidth: 1)
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
