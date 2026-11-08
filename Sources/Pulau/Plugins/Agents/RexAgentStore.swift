import Foundation
import Combine
import Darwin

enum RexAgent: String, CaseIterable {
    case pi = "Pi", codex = "Codex", claude = "Claude"

    static func identify(_ value: String?) -> RexAgent? {
        guard let value else { return nil }
        let name = (value as NSString).lastPathComponent.lowercased()
        switch name {
        case "pi", "pi.js": return .pi
        case "codex", "codex.js", "codex-cli": return .codex
        case "claude", "claude-code", "claude.js": return .claude
        default: return nil
        }
    }
}

enum RexAgentState: String, CaseIterable {
    case blocked, working, error, done, idle, unknown
}

struct RexAgentReport: Equatable {
    let agent: RexAgent
    let state: RexAgentState
    let isSubagent: Bool
    let identity: String?
    let taskTitle: String?
    let model: String?

    init(agent: RexAgent, state: RexAgentState, isSubagent: Bool = false, identity: String? = nil, taskTitle: String? = nil, model: String? = nil) {
        self.agent = agent
        self.state = state
        self.isSubagent = isSubagent
        self.identity = identity
        self.taskTitle = taskTitle
        self.model = model
    }
}

struct RexActivityGroup: Hashable {
    let agent: RexAgent
    let isSubagent: Bool
    let title: String?
    let model: String?
}

struct RexActivitySection {
    let state: RexAgentState
    let groups: [(key: RexActivityGroup, count: Int)]
    var count: Int { groups.reduce(0) { $0 + $1.count } }
}

struct RexSnapshot: Equatable {
    enum Connection { case checking, connected, partial, offline }
    let connection: Connection
    let reports: [RexAgentReport]

    static let offline = RexSnapshot(connection: .offline, reports: [])

    var activitySections: [RexActivitySection] {
        [RexAgentState.blocked, .error, .working, .idle, .done, .unknown].compactMap { state in
            let matching = reports.filter { $0.state == state }
            guard !matching.isEmpty else { return nil }
            let grouped = Dictionary(grouping: matching) {
                RexActivityGroup(agent: $0.agent, isSubagent: $0.isSubagent, title: $0.taskTitle, model: $0.model)
            }
            let groups = grouped.map { (key: $0.key, count: $0.value.count) }.sorted {
                let left = "\($0.key.agent.rawValue)|\($0.key.isSubagent)|\($0.key.title ?? "")|\($0.key.model ?? "")"
                let right = "\($1.key.agent.rawValue)|\($1.key.isSubagent)|\($1.key.title ?? "")|\($1.key.model ?? "")"
                return left < right
            }
            return RexActivitySection(state: state, groups: groups)
        }
    }

    var activitySummary: String {
        guard connection != .offline && connection != .checking else { return "Rex unavailable" }
        let counts = [RexAgentState.working, .done, .blocked, .error].compactMap { state -> String? in
            let count = reports.filter { $0.state == state }.count
            return count > 0 ? "\(count) \(state.rawValue)" : nil
        }
        let text = counts.isEmpty ? "No agent status" : counts.joined(separator: "  ·  ")
        return connection == .partial ? "\(text) · partial" : text
    }

    var summary: String {
        if connection == .checking { return "Rex connecting…" }
        guard connection != .offline else { return "Rex offline" }
        guard !reports.isEmpty else { return connection == .partial ? "Rex unavailable" : "Rex: no agents" }
        func describe(_ label: String, _ matching: [RexAgentReport]) -> String? {
            guard !matching.isEmpty else { return nil }
            let states = RexAgentState.allCases.compactMap { state -> String? in
                let count = matching.filter { $0.state == state }.count
                return count == 0 ? nil : "\(state.rawValue)\(count > 1 ? " \(count)" : "")"
            }
            return "\(label) \(states.joined(separator: "/"))"
        }
        var parts: [String] = []
        if let children = describe("Pi subagents", reports.filter { $0.agent == .pi && $0.isSubagent }) {
            parts.append(children)
        }
        parts += RexAgent.allCases.compactMap { agent in
            describe(agent.rawValue, reports.filter { $0.agent == agent && !$0.isSubagent })
        }
        return "\(connection == .partial ? "Rex partial: " : "Rex: ")\(parts.joined(separator: " · "))"
    }
}

enum RexClient {
    struct Sessions: Decodable { let sessions: [Session]? }
    struct Session: Decodable { let session_id: String }
    struct Blocks: Decodable { let blocks: [Block] }
    struct Block: Decodable { let block_id: String; let creator_name: String }
    struct Status: Decodable { let records: [Record] }
    struct Record: Decodable {
        let id: String?; let app: String?; let effective_app: String?; let state: String; let msg: String?

        var taskTitle: String? {
            guard let msg else { return nil }
            let line = msg.components(separatedBy: .newlines).first ?? ""
            let clean = String(String.UnicodeScalarView(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(80))
                .trimmingCharacters(in: .whitespaces)
            return clean.isEmpty ? nil : clean
        }
    }
    struct Processes: Decodable { let foreground: Foreground? }
    struct Foreground: Decodable { let name: String?; let argv0: String?; let script: String? }

    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
            "/opt/homebrew/bin/rex", "/usr/local/bin/rex", "/usr/bin/rex"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func run(_ executable: URL, _ args: [String]) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--autostart=false", "--timeout", "1s"] + args
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let handle = output.fileHandleForReading
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var data = Data()
        var failed = false
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            guard ProcessInfo.processInfo.systemUptime < deadline else { failed = true; break }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; failed = true; break }
            if ready == 0 { continue }
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                failed = true
                break
            }
            guard data.count + count <= 1_048_576 else { failed = true; break }
            data.append(contentsOf: buffer.prefix(count))
        }
        while !failed && process.isRunning {
            if ProcessInfo.processInfo.systemUptime >= deadline { failed = true; break }
            usleep(20_000)
        }
        if failed && process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        try? handle.close()
        process.waitUntilExit()
        return !failed && process.terminationStatus == 0 ? data : nil
    }

    static func decode<T: Decodable>(_ type: T.Type, executable: URL, args: [String]) -> T? {
        guard let data = run(executable, args) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func snapshot() -> RexSnapshot {
        guard let executable,
              let sessions = decode(Sessions.self, executable: executable, args: ["ls", "--json"]) else { return .offline }
        var reports: [RexAgentReport] = []
        var partial = (sessions.sessions?.count ?? 0) > 32
        let deadline = Date().addingTimeInterval(8)
        var terminals = 0
        for session in (sessions.sessions ?? []).prefix(32) {
            guard Date() < deadline else { partial = true; break }
            guard let blocks = decode(Blocks.self, executable: executable, args: ["block", "ls", "-s", session.session_id, "--json"]) else {
                partial = true
                continue
            }
            for block in blocks.blocks where block.creator_name == "com.superlogical.terminal" {
                guard terminals < 64, Date() < deadline else { partial = true; break }
                terminals += 1
                let prefix = ["block", "call", "-s", session.session_id, "-b", block.block_id]
                guard let status = decode(Status.self, executable: executable, args: prefix + ["program_status", "{}"]) else {
                    partial = true
                    continue
                }
                let processes = Date() < deadline
                    ? decode(Processes.self, executable: executable, args: prefix + ["process", "{}"])
                    : nil
                if processes == nil { partial = true }
                reports.append(contentsOf: reportsForBlock(status: status, foreground: processes?.foreground,
                                                           scope: "\(session.session_id)|\(block.block_id)"))
            }
        }
        return RexSnapshot(connection: partial ? .partial : .connected, reports: reports)
    }

    static func reportsForBlock(status: Status, foreground: Foreground?, scope: String? = nil) -> [RexAgentReport] {
        var found: [RexAgent: RexAgentState] = [:]
        var subagents: [RexAgentReport] = []
        var childIDs = Set<String>()
        let piModel = status.records.first { $0.id == "pulau-subagents/model" && RexAgent.identify($0.effective_app ?? $0.app) == .pi }?.taskTitle
        for record in status.records {
            if record.id == "pulau-subagents/model" { continue }
            guard let agent = RexAgent.identify(record.effective_app ?? record.app) else { continue }
            let state = RexAgentState(rawValue: record.state) ?? .unknown
            if agent == .pi, let id = record.id, id.hasPrefix("pulau-subagents/") {
                if childIDs.insert(id).inserted {
                    subagents.append(RexAgentReport(agent: agent, state: state, isSubagent: true,
                                                    identity: scope.map { "\($0)|\(id)" }, taskTitle: state == .working ? record.taskTitle : nil))
                }
                continue
            }
            if let previous = found[agent],
               let oldPriority = RexAgentState.allCases.firstIndex(of: previous),
               let newPriority = RexAgentState.allCases.firstIndex(of: state), oldPriority <= newPriority { continue }
            found[agent] = state
        }
        if let foreground,
           let agent = RexAgent.identify(foreground.script) ?? RexAgent.identify(foreground.argv0) ?? RexAgent.identify(foreground.name),
           found[agent] == nil { found[agent] = .unknown }
        return RexAgent.allCases.compactMap { agent in
            found[agent].map { RexAgentReport(agent: agent, state: $0, identity: scope.map { "\($0)|\(agent.rawValue)" },
                                               model: agent == .pi ? piModel : nil) }
        } + subagents
    }
}

@MainActor
final class RexAgentStore: ObservableObject {
    @Published private(set) var snapshot = RexSnapshot(connection: .checking, reports: [])
    @Published private(set) var activityEvent: RexAgentReport?
    private var polling: Task<Void, Never>?
    private var fetch: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var refreshPending = false
    private var generation = 0
    private var eventProcess: Process?
    private var eventPipe: Pipe?
    private var eventBuffer = Data()

    init() {
        refresh()
        startEvents()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.refresh()
                self?.startEvents()
            }
        }
    }

    private func refresh() {
        guard fetch == nil else { refreshPending = true; return }
        let currentGeneration = generation
        fetch = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { RexClient.snapshot() }.value
            guard let self, !Task.isCancelled else { return }
            if generation == currentGeneration { snapshot = result }
            fetch = nil
            if refreshPending { refreshPending = false; refresh() }
        }
    }

    private func startEvents() {
        guard eventProcess?.isRunning != true, let executable = RexClient.executable else { return }
        eventPipe?.fileHandleForReading.readabilityHandler = nil
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--autostart=false", "--timeout", "1s", "events", "--all", "--json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] stopped in
            Task { @MainActor [weak self] in self?.eventsStopped(stopped) }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in self?.receiveEvents(data) }
        }
        do {
            try process.run()
            eventBuffer.removeAll()
            eventPipe = pipe
            eventProcess = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            scheduleReconnect()
        }
    }

    private func eventsStopped(_ process: Process) {
        guard eventProcess === process else { return }
        eventPipe?.fileHandleForReading.readabilityHandler = nil
        eventPipe = nil
        eventProcess = nil
        eventBuffer.removeAll()
        generation += 1
        if fetch != nil { refreshPending = true }
        snapshot = .offline
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.refresh()
            self?.startEvents()
        }
    }

    private func receiveEvents(_ data: Data) {
        eventBuffer.append(data)
        guard eventBuffer.count <= 1_048_576 else { eventBuffer.removeAll(); refresh(); return }
        var relevant = false
        while let index = eventBuffer.firstIndex(of: 10) {
            let line = Data(eventBuffer[..<index])
            eventBuffer.removeSubrange(...index)
            guard let event = try? JSONDecoder().decode(RexEvent.self, from: line) else { continue }
            if var report = event.statusReport {
                if report.agent == .pi && !report.isSubagent,
                   let previous = snapshot.reports.first(where: { $0.identity == report.identity }), let model = previous.model {
                    report = RexAgentReport(agent: report.agent, state: report.state, identity: report.identity, model: model)
                }
                generation += 1
                if fetch != nil { refreshPending = true }
                activityEvent = report
                if snapshot.connection == .connected || snapshot.connection == .partial {
                    var reports = snapshot.reports.filter { $0.identity != report.identity }
                    reports.append(report)
                    snapshot = RexSnapshot(connection: snapshot.connection, reports: reports)
                }
            }
            if let removal = event.removal, snapshot.connection == .connected || snapshot.connection == .partial {
                generation += 1
                if fetch != nil { refreshPending = true }
                let identities = Set(removal.ids.flatMap { id -> [String] in
                    if id.isEmpty { return RexAgent.allCases.map { "\(removal.scope)|\($0.rawValue)" } }
                    return id.hasPrefix("pulau-subagents/") ? ["\(removal.scope)|\(id)"] : []
                })
                snapshot = RexSnapshot(connection: snapshot.connection, reports: snapshot.reports.filter {
                    guard let identity = $0.identity else { return true }
                    return !identities.contains(identity)
                })
            }
            if event.isRelevant { relevant = true }
        }
        if relevant {
            debounce?.cancel()
            debounce = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                self?.refresh()
            }
        }
    }

    deinit {
        polling?.cancel()
        fetch?.cancel()
        debounce?.cancel()
        reconnect?.cancel()
        eventPipe?.fileHandleForReading.readabilityHandler = nil
        if let eventProcess, eventProcess.isRunning { eventProcess.terminate() }
    }
}

struct RexEvent: Decodable {
    struct Payload: Decodable { let session_id: String?; let event: InnerEvent? }
    struct InnerEvent: Decodable { let type: String; let payload: BlockPayload? }
    struct BlockPayload: Decodable { let block_id: String?; let name: String?; let payload: StatusPayload? }
    struct StatusPayload: Decodable { let id: String?; let ids: [String]?; let record: RexClient.Record? }
    let type: String
    let payload: Payload?

    var statusReport: RexAgentReport? {
        guard type == "session_event", let session = payload?.session_id,
              let event = payload?.event, event.type == "block_event",
              let block = event.payload, block.name == "program_status_changed",
              let blockID = block.block_id, let record = block.payload?.record,
              let agent = RexAgent.identify(record.effective_app ?? record.app) else { return nil }
        let id = block.payload?.id ?? record.id
        if id == "pulau-subagents/model" { return nil }
        let child = agent == .pi && (id?.hasPrefix("pulau-subagents/") ?? false)
        if let id, !id.isEmpty && !child { return nil }
        let suffix = child ? (id ?? agent.rawValue) : agent.rawValue
        return RexAgentReport(agent: agent, state: RexAgentState(rawValue: record.state) ?? .unknown,
                              isSubagent: child, identity: "\(session)|\(blockID)|\(suffix)",
                              taskTitle: child && record.state == "working" ? record.taskTitle : nil)
    }

    var removal: (scope: String, ids: [String])? {
        guard type == "session_event", let session = payload?.session_id,
              let event = payload?.event, event.type == "block_event", let block = event.payload,
              block.name == "program_status_removed", let blockID = block.block_id,
              let ids = block.payload?.ids else { return nil }
        return ("\(session)|\(blockID)", ids)
    }

    var isRelevant: Bool {
        if ["session_created", "session_destroyed", "session_removed"].contains(type) { return true }
        guard type == "session_event", let event = payload?.event else { return false }
        guard event.type == "block_event" else {
            return ["block_created", "block_closed", "window_created", "window_closed"].contains(event.type)
        }
        return ["program_status_changed", "program_status_removed", "process_changed", "child_exited"].contains(event.payload?.name ?? "")
    }
}
