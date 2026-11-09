import AppKit
import SwiftUI

// Motion tokens modeled on NotchIsland: springy open, quicker close, ease
// instead of spring when Reduce Motion is on.
enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    // Lively open with a controlled settle.
    static var spring: Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.83) }
    // A finite curve lets the panel hide as soon as the collapse finishes.
    static var dismissDuration: Double { reduce ? 0.1 : 0.2 }
    static func quick(duration: Double) -> Animation { .easeOut(duration: duration) }
}

/// Island look presets selectable from the menu; persisted per launch.
enum IslandLook: String, CaseIterable {
    case glassy
    case solid
    case systemExperimental
}

enum ExpandPreference: String {
    case `default`, minimal
}

enum IslandState {
    case collapsed, minimal, full

    var width: CGFloat { self == .collapsed ? 185 : 360 }

    /// Notification banners stay compact.
    func height(notification: Bool) -> CGFloat {
        self == .full ? (notification ? 84 : 174) : 32
    }
}

struct QuotaAlert {
    let provider: QuotaThresholdTracker.Provider
    let remaining: Int
}

struct AgentActionRequest: Equatable {
    let agent: String
    let question: String
}

struct AgentActivity: Equatable {
    enum Stage { case working, done }
    let stage: Stage
    let label: String
    let accessibility: String
    let details: [String]
    let taskTitles: [String]
    let piModels: [String]
    let hasPiSession: Bool
    let hasUnknownPiModel: Bool
    /// Root agent waiting on the user, with the dialog question.
    let action: AgentActionRequest?

    init(stage: Stage, reports: [RexAgentReport]) {
        self.stage = stage
        let agents = RexAgent.allCases.filter { agent in reports.contains { $0.agent == agent } }
        if agents.count == 1, let agent = agents.first {
            let name = agent == .pi ? "Pi" : (agent == .codex ? "Cx" : "Cl")
            label = reports.count > 1 ? "\(name)\(reports.count)" : name
        } else {
            label = "\(reports.count)"
        }
        accessibility = "\(agents.map(\.rawValue).joined(separator: ", ")), \(reports.count) agent\(reports.count == 1 ? "" : "s") \(stage == .working ? "working" : "done")"
        taskTitles = Array(Set(reports.compactMap(\.taskTitle))).sorted()
        let sessions = reports.filter { $0.agent == .pi && !$0.isSubagent }
        hasPiSession = !sessions.isEmpty
        hasUnknownPiModel = sessions.contains { $0.model == nil }
        piModels = Array(Set(sessions.compactMap(\.model))).sorted()
        if let waiting = reports.first(where: { !$0.isSubagent && $0.state == .blocked && $0.actionQuestion != nil }) {
            action = AgentActionRequest(agent: waiting.agent.rawValue, question: waiting.actionQuestion ?? "")
        } else {
            action = nil
        }
        details = RexAgent.allCases.flatMap { agent in
            [false, true].compactMap { subagent in
                let count = reports.filter { $0.agent == agent && $0.isSubagent == subagent }.count
                guard count > 0 else { return nil }
                return "\(agent.rawValue)\(subagent ? " subagent\(count == 1 ? "" : "s")" : "") · \(count) \(stage == .working ? "working" : "done")"
            }
        }
    }
}

@MainActor
final class BannerPresenter: ObservableObject {
    @Published private(set) var note: PulauNotification?
    @Published private(set) var quotaAlert: QuotaAlert?
    @Published private(set) var agentActivity: AgentActivity?
    @Published private(set) var agentActivityVisible = false
    @Published var agentDetailHovered = false
    @Published private(set) var state: IslandState = .collapsed
    @Published var expandPreference: ExpandPreference = .default {
        didSet {
            if note == nil && hovered { showHoverState() }
        }
    }
    @Published private(set) var generation = UUID()
    private(set) var hovered = false
    private var activityTracker = AgentActivityTracker()
    private var workingAgents: [RexAgentReport] = []
    private var pendingAgentDone: [AgentActivity] = []
    private var activeAgentDone: AgentActivity?
    private var activityTimer: Task<Void, Never>?
    private var activityGeneration = UUID()
    private var lastActionQuestion: String?
    @Published var look: IslandLook = UserDefaults.standard.string(forKey: "islandLook").flatMap(IslandLook.init(rawValue:)) ?? .glassy

    func present(_ notification: PulauNotification, quotaAlert: QuotaAlert? = nil) {
        activityGeneration = UUID()
        agentActivityVisible = false
        agentDetailHovered = false
        if let activeAgentDone {
            pendingAgentDone.insert(activeAgentDone, at: 0)
            self.activeAgentDone = nil
            activityTimer?.cancel()
            activityTimer = nil
        }
        if quotaAlert != nil { state = .collapsed }
        self.quotaAlert = quotaAlert
        note = notification
        generation = UUID()
    }

    func expandFromView() {
        withAnimation(Motion.spring) { state = .full }
    }

    private func showHoverState() {
        withAnimation(Motion.spring) { state = expandPreference == .minimal ? .minimal : .full }
    }

    func setHovered(_ value: Bool) {
        hovered = value
        guard note == nil else { return }
        if value { showHoverState() } else { dismiss() }
    }

    func dismiss(duration: Double = Motion.dismissDuration) {
        let target: IslandState = note != nil && quotaAlert == nil && hovered
            ? (expandPreference == .minimal ? .minimal : .full)
            : .collapsed
        withAnimation(Motion.quick(duration: duration)) { state = target }
    }

    func clear() {
        quotaAlert = nil
        note = nil
        if hovered { showHoverState() }
        else if state != .collapsed { withAnimation(Motion.quick(duration: Motion.dismissDuration)) { state = .collapsed } }
        updateAgentPresentation()
    }

    func updateAgentActivity(_ snapshot: RexSnapshot) {
        applyAgentActivity(activityTracker.update(snapshot))
    }

    func updateAgentActivity(event: RexAgentReport) {
        applyAgentActivity(activityTracker.update(event: event))
    }

    private func applyAgentActivity(_ update: AgentActivityUpdate) {
        let wasWorking = !workingAgents.isEmpty
        workingAgents = update.working
        presentActionIfNeeded()
        if !wasWorking && !workingAgents.isEmpty {
            pendingAgentDone.removeAll()
            if activeAgentDone != nil {
                activityTimer?.cancel()
                activityTimer = nil
                activeAgentDone = nil
            }
        }
        if !update.completed.isEmpty {
            pendingAgentDone.append(AgentActivity(stage: .done, reports: update.completed))
        }
        updateAgentPresentation()
    }

    /// Surfaces a needs-input banner the first time a question appears; repeats
    /// only when the question text changes.
    private func presentActionIfNeeded() {
        guard let activity = workingAgents.isEmpty ? nil : AgentActivity(stage: .working, reports: workingAgents),
              let action = activity.action else {
            lastActionQuestion = nil
            return
        }
        guard action.question != lastActionQuestion, note == nil else { return }
        lastActionQuestion = action.question
        let notification = PulauNotification(app: action.agent, title: "Needs your input", body: action.question)
        present(notification)
        withAnimation(Motion.spring) { state = .full }
        let generation = UUID()
        activityGeneration = generation
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, self.note == notification else { return }
            self.dismiss()
            try? await Task.sleep(for: .seconds(Motion.dismissDuration))
            guard self.note == notification else { return }
            self.clear()
        }
    }

    private func updateAgentPresentation() {
        guard note == nil, activeAgentDone == nil else { return }
        if !pendingAgentDone.isEmpty {
            let done = pendingAgentDone.removeFirst()
            activeAgentDone = done
            showAgentActivity(done)
            let displayTime = 2 + (Motion.reduce ? 0 : QuotaLiquidAlert.duration)
            activityTimer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(displayTime)) } catch { return }
                self?.finishAgentDone()
            }
        } else if !workingAgents.isEmpty {
            showAgentActivity(AgentActivity(stage: .working, reports: workingAgents))
        } else {
            hideAgentActivity()
        }
    }

    func finishAgentDone() {
        guard activeAgentDone != nil else { return }
        activityTimer?.cancel()
        activityTimer = nil
        activeAgentDone = nil
        updateAgentPresentation()
    }

    private func showAgentActivity(_ activity: AgentActivity) {
        if activity.stage != .working { agentDetailHovered = false }
        activityTimer?.cancel()
        activityTimer = nil
        let generation = UUID()
        activityGeneration = generation
        agentActivity = activity
        guard !agentActivityVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activityGeneration == generation, self.agentActivity != nil else { return }
            withAnimation(Motion.spring) { self.agentActivityVisible = true }
        }
    }

    private func hideAgentActivity() {
        if agentDetailHovered { agentDetailHovered = false }
        guard agentActivity != nil else { return }
        activityGeneration = UUID()
        guard agentActivityVisible else {
            if activityTimer == nil { agentActivity = nil }
            return
        }
        let duration = Motion.reduce ? Motion.dismissDuration : QuotaLiquidAlert.duration
        withAnimation(Motion.quick(duration: duration)) { agentActivityVisible = false }
        activityTimer?.cancel()
        activityTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, !self.agentActivityVisible else { return }
            self.agentActivity = nil
            self.activityTimer = nil
        }
    }
}

