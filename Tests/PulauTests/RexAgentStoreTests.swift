import XCTest
@testable import Pulau

final class RexAgentStoreTests: XCTestCase {
    func testReportsAreAllowlistedAndDeduplicatedPerBlock() throws {
        let data = Data(#"{"records":[{"app":"pi","state":"working"},{"effective_app":"pi","state":"blocked","msg":"private"},{"app":"other","state":"working"},{"app":"codex","state":"future"}]}"#.utf8)
        let status = try JSONDecoder().decode(RexClient.Status.self, from: data)
        let process = RexClient.Foreground(name: "node", argv0: "node", script: "/example/claude.js")
        XCTAssertEqual(RexClient.reportsForBlock(status: status, foreground: process), [
            RexAgentReport(agent: .pi, state: .blocked),
            RexAgentReport(agent: .codex, state: .unknown),
            RexAgentReport(agent: .claude, state: .unknown),
        ])
    }

    func testPiSubagentsRemainSeparateFromParent() throws {
        let data = Data(#"{"records":[{"app":"pi","state":"working"},{"id":"pulau-subagents/0123456789abcdef","effective_app":"pi","state":"working"},{"id":"pulau-subagents/fedcba9876543210","app":"pi","state":"blocked"},{"id":"pulau-subagents/fedcba9876543210","app":"pi","state":"blocked"}]}"#.utf8)
        let status = try JSONDecoder().decode(RexClient.Status.self, from: data)
        let reports = RexClient.reportsForBlock(status: status, foreground: nil)
        XCTAssertEqual(reports.filter { !$0.isSubagent }, [RexAgentReport(agent: .pi, state: .working)])
        XCTAssertEqual(reports.filter(\.isSubagent).count, 2)
        XCTAssertEqual(RexSnapshot(connection: .connected, reports: reports).summary, "Rex: Pi subagents blocked/working · Pi working")
    }

    func testPiModelMetadataIsAttachedToParentNotCountedAsAgent() throws {
        let data = Data(#"{"records":[{"app":"pi","state":"working"},{"id":"pulau-subagents/model","app":"pi","state":"idle","msg":"anthropic/claude-sonnet"}]}"#.utf8)
        let status = try JSONDecoder().decode(RexClient.Status.self, from: data)
        let reports = RexClient.reportsForBlock(status: status, foreground: nil, scope: "s|b")
        XCTAssertEqual(reports, [RexAgentReport(agent: .pi, state: .working, identity: "s|b|Pi", model: "anthropic/claude-sonnet")])
        let event = Data(#"{"type":"session_event","payload":{"session_id":"s","event":{"type":"block_event","payload":{"block_id":"b","name":"program_status_changed","payload":{"id":"pulau-subagents/model","record":{"app":"pi","state":"idle","msg":"anthropic/claude-sonnet"}}}}}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(RexEvent.self, from: event).statusReport)
    }

    func testOnlyWorkingPluginChildrenExposeSanitizedTaskTitles() throws {
        let data = Data(#"{"records":[{"app":"pi","state":"working","msg":"root secret"},{"id":"pulau-subagents/123","app":"pi","state":"working","msg":"Task\u001b!\nsecond line"},{"id":"pulau-subagents/456","app":"pi","state":"done","msg":"old task"}]}"#.utf8)
        let status = try JSONDecoder().decode(RexClient.Status.self, from: data)
        let reports = RexClient.reportsForBlock(status: status, foreground: nil)
        XCTAssertNil(reports.first { !$0.isSubagent }?.taskTitle)
        XCTAssertEqual(reports.first { $0.isSubagent && $0.state == .working }?.taskTitle, "Task!")
        XCTAssertNil(reports.first { $0.isSubagent && $0.state == .done }?.taskTitle)
    }

    func testSummaryDoesNotEquateOfflineWithIdle() {
        XCTAssertEqual(RexSnapshot.offline.summary, "Rex offline")
        XCTAssertEqual(RexSnapshot(connection: .checking, reports: []).summary, "Rex connecting…")
        XCTAssertEqual(RexSnapshot(connection: .connected, reports: []).summary, "Rex: no agents")
        XCTAssertEqual(RexSnapshot(connection: .partial, reports: []).summary, "Rex unavailable")
        let reports = [RexAgentReport(agent: .pi, state: .working), RexAgentReport(agent: .pi, state: .working), RexAgentReport(agent: .codex, state: .unknown)]
        XCTAssertEqual(RexSnapshot(connection: .connected, reports: reports).summary, "Rex: Pi working 2 · Codex unknown")
        let mixed = [RexAgentReport(agent: .pi, state: .working), RexAgentReport(agent: .pi, state: .blocked)]
        XCTAssertEqual(RexSnapshot(connection: .connected, reports: mixed).summary, "Rex: Pi blocked/working")
    }

    func testActivitySectionsGroupCountsAndKeepAvailableDetails() {
        let reports = [RexAgentReport(agent: .pi, state: .working, model: "provider/model"),
                       RexAgentReport(agent: .pi, state: .working, isSubagent: true, taskTitle: "Build"),
                       RexAgentReport(agent: .pi, state: .done, isSubagent: true),
                       RexAgentReport(agent: .pi, state: .done, isSubagent: true)]
        let sections = RexSnapshot(connection: .connected, reports: reports).activitySections
        XCTAssertEqual(sections.map(\.state), [.working, .done])
        XCTAssertEqual(sections.map(\.count), [2, 2])
        XCTAssertTrue(sections[0].groups.contains { $0.key.title == "Build" && $0.key.isSubagent })
        XCTAssertTrue(sections[0].groups.contains { $0.key.model == "provider/model" && !$0.key.isSubagent })
        XCTAssertEqual(sections[1].groups.count, 1)
        XCTAssertEqual(sections[1].groups[0].count, 2)
    }

    func testCompactActivitySummary() {
        let reports = [RexAgentReport(agent: .pi, state: .working), RexAgentReport(agent: .pi, state: .done, isSubagent: true),
                       RexAgentReport(agent: .pi, state: .done, isSubagent: true)]
        XCTAssertEqual(RexSnapshot(connection: .connected, reports: reports).activitySummary, "1 working  ·  2 done")
        XCTAssertEqual(RexSnapshot(connection: .partial, reports: reports).activitySummary, "1 working  ·  2 done · partial")
        XCTAssertEqual(RexSnapshot.offline.activitySummary, "Rex unavailable")
    }

    func testCommandTimeoutKillsUnresponsiveProcess() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulau-rex-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try "#!/bin/sh\nexec 1>&-\nexec sleep 30\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(RexClient.run(url, []))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 5)
    }

    func testLiveRexSnapshotWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["PULAU_TEST_REX"] == "1" else { throw XCTSkip("Live Rex test not requested") }
        let snapshot = RexClient.snapshot()
        XCTAssertNotEqual(snapshot.connection, .offline)
        XCTAssertTrue(snapshot.reports.contains { $0.agent == .pi })
    }

    func testLiveRexSubagentWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["PULAU_TEST_REX_CHILD"] == "1" else { throw XCTSkip("Live Rex child test not requested") }
        let snapshot = RexClient.snapshot()
        XCTAssertTrue(snapshot.reports.contains { $0.agent == .pi && $0.isSubagent && $0.state == .working })
    }

    @MainActor
    func testLiveRexStoreWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["PULAU_TEST_REX"] == "1" else { throw XCTSkip("Live Rex test not requested") }
        let store = RexAgentStore()
        for _ in 0..<40 {
            if store.snapshot.reports.contains(where: { $0.agent == .pi }) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTFail("Live Rex store did not report Pi")
    }

    func testEventFilteringIgnoresUnrelatedEvents() throws {
        func parse(_ json: String) throws -> RexEvent { try JSONDecoder().decode(RexEvent.self, from: Data(json.utf8)) }
        XCTAssertTrue(try parse(#"{"type":"session_event","payload":{"event":{"type":"block_event","payload":{"name":"program_status_changed","payload":{"msg":"secret"}}}}}"#).isRelevant)
        XCTAssertFalse(try parse(#"{"type":"session_event","payload":{"event":{"type":"block_event","payload":{"name":"clipboard_written"}}}}"#).isRelevant)
        let status = try parse(#"{"type":"session_event","payload":{"session_id":"s","event":{"type":"block_event","payload":{"block_id":"b","name":"program_status_changed","payload":{"id":"pulau-subagents/0123456789abcdef","record":{"app":"pi","state":"working","msg":"private"}}}}}}"#)
        XCTAssertEqual(status.statusReport, RexAgentReport(agent: .pi, state: .working, isSubagent: true, identity: "s|b|pulau-subagents/0123456789abcdef", taskTitle: "private"))
        let removal = try parse(#"{"type":"session_event","payload":{"session_id":"s","event":{"type":"block_event","payload":{"block_id":"b","name":"program_status_removed","payload":{"ids":["pulau-subagents/0123456789abcdef"]}}}}}"#)
        XCTAssertEqual(removal.removal?.scope, "s|b")
        XCTAssertEqual(removal.removal?.ids, ["pulau-subagents/0123456789abcdef"])
        XCTAssertTrue(try parse(#"{"type":"session_created","payload":{}}"#).isRelevant)
        XCTAssertTrue(try parse(#"{"type":"session_destroyed","payload":{}}"#).isRelevant)
        XCTAssertFalse(try parse(#"{"type":"session_event","payload":{"event":{"type":"active_window_changed","payload":{}}}}"#).isRelevant)
    }
}
