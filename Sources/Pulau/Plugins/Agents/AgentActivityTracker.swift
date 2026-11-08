import Foundation

struct AgentActivityUpdate {
    let working: [RexAgentReport]
    let completed: [RexAgentReport]
}

struct AgentActivityTracker {
    private var previous: [String: RexAgentReport]?
    private var visibleWorking: [String: RexAgentReport] = [:]
    private var uncertain = false

    mutating func update(_ snapshot: RexSnapshot) -> AgentActivityUpdate {
        guard snapshot.connection == .connected || snapshot.connection == .partial else {
            previous = nil
            visibleWorking.removeAll()
            uncertain = false
            return AgentActivityUpdate(working: [], completed: [])
        }
        let working = snapshot.reports.filter { $0.state == .working || $0.state == .blocked }
        visibleWorking = Dictionary(working.compactMap { report in report.identity.map { ($0, report) } }, uniquingKeysWith: { _, last in last })
        guard snapshot.connection == .connected else {
            uncertain = true
            if previous == nil { previous = [:] }
            for report in snapshot.reports {
                if let id = report.identity, report.state == .working || previous?[id] == nil { previous?[id] = report }
            }
            return AgentActivityUpdate(working: working, completed: [])
        }
        let completed = snapshot.reports.filter { report in
            guard !uncertain else { return false }
            guard report.state == .done, let id = report.identity, let old = previous?[id]?.state else { return false }
            return old == .working || old == .blocked
        }
        var current: [String: RexAgentReport] = [:]
        for report in snapshot.reports {
            if let id = report.identity { current[id] = report }
        }
        previous = current
        uncertain = false
        return AgentActivityUpdate(working: working, completed: completed)
    }

    mutating func update(event report: RexAgentReport) -> AgentActivityUpdate {
        guard let id = report.identity else {
            return AgentActivityUpdate(working: Array(visibleWorking.values), completed: [])
        }
        let old = previous?[id]?.state
        if previous == nil { previous = [:] }
        previous?[id] = report
        if report.state == .working || report.state == .blocked { visibleWorking[id] = report }
        else { visibleWorking.removeValue(forKey: id) }
        let completed = report.state == .done && (old == .working || old == .blocked) ? [report] : []
        return AgentActivityUpdate(working: Array(visibleWorking.values), completed: completed)
    }
}
