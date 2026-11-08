import XCTest
import Combine
@testable import Pulau

@MainActor
final class AgentActivityTests: XCTestCase {
    private func report(_ id: String, _ state: RexAgentState, _ agent: RexAgent = .pi, child: Bool = false) -> RexAgentReport {
        RexAgentReport(agent: agent, state: state, isSubagent: child, identity: id)
    }

    func testEyesLookLeftAndRightWithinBounds() {
        XCTAssertEqual(AgentEyes.gazeOffset(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AgentEyes.gazeOffset(at: 1), 1.4, accuracy: 0.001)
        XCTAssertEqual(AgentEyes.gazeOffset(at: 3), -1.4, accuracy: 0.001)
        XCTAssertEqual(AgentEyes.gazeOffset(at: 4), 0, accuracy: 0.001)
    }

    func testBuddyBlinksOnCadenceAndMoodFollowsAgents() {
        XCTAssertEqual(AgentEyes.blinkScale(at: 0), 1, accuracy: 0.001)
        XCTAssertEqual(AgentEyes.blinkScale(at: 2), 1, accuracy: 0.001)
        XCTAssertLessThan(AgentEyes.blinkScale(at: 0.07), 0.2)
        XCTAssertEqual(AgentEyes.mouthWidth(at: 0.9, animate: true), 4.6, accuracy: 0.001)
        XCTAssertEqual(AgentEyes.mouthWidth(at: 0, animate: true), 3, accuracy: 0.001)
        XCTAssertEqual(AgentEyes.mouthWidth(at: 0, animate: false), 4)
        XCTAssertEqual(AgentEyes.mood(stage: .working, hasBlocked: false, hasError: false), .glance)
        XCTAssertEqual(AgentEyes.mood(stage: .working, hasBlocked: true, hasError: false), .curious)
        XCTAssertEqual(AgentEyes.mood(stage: .working, hasBlocked: false, hasError: true), .dizzy)
        XCTAssertEqual(AgentEyes.mood(stage: .working, hasBlocked: true, hasError: true), .dizzy)
    }

    func testActivityLabelsIncludeAgentAndCount() {
        let reports = [report("a", .working), report("b", .working, .pi, child: true)]
        let activity = AgentActivity(stage: .working, reports: reports)
        XCTAssertEqual(activity.label, "Pi2")
        XCTAssertTrue(activity.accessibility.contains("2 agents working"))
        XCTAssertEqual(activity.details, ["Pi · 1 working", "Pi subagent · 1 working"])
    }

    func testWorkingDetailsGroupAgentsAndSubagents() {
        let reports = [report("a", .working, .pi, child: true), report("b", .working, .pi, child: true),
                       report("c", .working, .codex), report("d", .working, .claude)]
        XCTAssertEqual(AgentActivity(stage: .working, reports: reports).details,
                       ["Pi subagents · 2 working", "Codex · 1 working", "Claude · 1 working"])
    }

    func testActivityIncludesPiSessionModelsWithoutGuessingSubagents() {
        let reports = [RexAgentReport(agent: .pi, state: .working, model: "anthropic/claude-sonnet"),
                       RexAgentReport(agent: .pi, state: .working),
                       RexAgentReport(agent: .pi, state: .working, isSubagent: true, model: "ignored")]
        let activity = AgentActivity(stage: .working, reports: reports)
        XCTAssertEqual(activity.piModels, ["anthropic/claude-sonnet"])
        XCTAssertTrue(activity.hasUnknownPiModel)
    }

    func testActivityIncludesAvailableTaskTitles() {
        let reports = [RexAgentReport(agent: .pi, state: .working, isSubagent: true, taskTitle: "Build"),
                       RexAgentReport(agent: .pi, state: .working, isSubagent: true, taskTitle: "Review")]
        XCTAssertEqual(AgentActivity(stage: .working, reports: reports).taskTitles, ["Build", "Review"])
    }

    func testAgentHoverIncludesBubbleAndOpenDetailsOnly() {
        let frame = NSRect(x: 100, y: 200, width: 440, height: 190)
        let x = frame.minX + QuotaLiquidAlert.restingX(notchWidth: 185)
        let bubble = NSPoint(x: x, y: frame.maxY - 16)
        let details = NSPoint(x: x, y: frame.maxY - 60)
        XCTAssertTrue(NotificationWatcher.agentHoverContains(bubble, frame: frame, notchWidth: 185, includeDetail: false, detailHeight: 190))
        XCTAssertFalse(NotificationWatcher.agentHoverContains(details, frame: frame, notchWidth: 185, includeDetail: false, detailHeight: 190))
        XCTAssertTrue(NotificationWatcher.agentHoverContains(details, frame: frame, notchWidth: 185, includeDetail: true, detailHeight: 190))
        XCTAssertFalse(NotificationWatcher.agentHoverContains(NSPoint(x: frame.midX, y: frame.maxY - 16), frame: frame,
                                                            notchWidth: 185, includeDetail: true, detailHeight: 190))
        XCTAssertFalse(NotificationWatcher.agentHoverContains(NSPoint(x: frame.minX, y: frame.minY), frame: frame, notchWidth: 185, includeDetail: true, detailHeight: 190))
        XCTAssertFalse(NotificationWatcher.agentHoverContains(NSPoint(x: x, y: frame.maxY - 160), frame: frame,
                                                               notchWidth: 185, includeDetail: true, detailHeight: 84))
        let snapshot = RexSnapshot(connection: .connected, reports: [report("a", .working)])
        XCTAssertEqual(QuotaLiquidAlert.detailHeight(for: snapshot, available: 490), 190)
        XCTAssertEqual(QuotaLiquidAlert.detailHeight(for: snapshot, available: 180), 180)
    }

    func testOverlappingAgentsAndDoneTransitions() {
        var tracker = AgentActivityTracker()
        let first = tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .working), report("b", .working, .codex)]))
        XCTAssertEqual(first.working.count, 2)
        XCTAssertTrue(first.completed.isEmpty)
        let next = tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .done), report("b", .working, .codex)]))
        XCTAssertEqual(next.working.map(\.identity), ["b"])
        XCTAssertEqual(next.completed.map(\.identity), ["a"])
        XCTAssertTrue(tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .done), report("b", .working, .codex)])).completed.isEmpty)
    }

    func testIncompleteSnapshotsDoNotInventDone() {
        var tracker = AgentActivityTracker()
        _ = tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .working)]))
        XCTAssertTrue(tracker.update(.offline).completed.isEmpty)
        XCTAssertTrue(tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .done)])).completed.isEmpty)
        _ = tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .working)]))
        XCTAssertTrue(tracker.update(RexSnapshot(connection: .partial, reports: [])).completed.isEmpty)
        XCTAssertTrue(tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .done)])).completed.isEmpty)
        XCTAssertTrue(tracker.update(RexSnapshot(connection: .connected, reports: [report("new", .done)])).completed.isEmpty)
    }

    func testPartialSnapshotPreservesEventHistoryWithoutInventingCompletion() {
        var tracker = AgentActivityTracker()
        _ = tracker.update(RexSnapshot(connection: .connected, reports: [report("a", .working), report("b", .working, .codex)]))
        let partial = tracker.update(RexSnapshot(connection: .partial, reports: [report("b", .working, .codex)]))
        XCTAssertEqual(partial.working.map(\.identity), ["b"])
        XCTAssertTrue(partial.completed.isEmpty)
        let event = tracker.update(event: report("a", .done))
        XCTAssertEqual(event.completed.map(\.identity), ["a"])
        XCTAssertEqual(event.working.map(\.identity), ["b"])
    }

    func testRepeatedEmptyUpdatesDoNotCutOffMerge() async throws {
        let presenter = BannerPresenter()
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .working)]))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(presenter.agentActivityVisible)
        presenter.updateAgentActivity(.offline)
        XCTAssertFalse(presenter.agentActivityVisible)
        XCTAssertNotNil(presenter.agentActivity)
        presenter.updateAgentActivity(.offline)
        XCTAssertNotNil(presenter.agentActivity)
    }

    func testFastWorkingAndDoneEventsAreNotLostBetweenSnapshots() {
        var tracker = AgentActivityTracker()
        _ = tracker.update(RexSnapshot(connection: .connected, reports: []))
        let started = tracker.update(event: report("child", .working, .pi, child: true))
        XCTAssertEqual(started.working.count, 1)
        let finished = tracker.update(event: report("child", .done, .pi, child: true))
        XCTAssertTrue(finished.working.isEmpty)
        XCTAssertEqual(finished.completed.count, 1)
        XCTAssertTrue(tracker.update(event: report("child", .done, .pi, child: true)).completed.isEmpty)
        XCTAssertTrue(tracker.update(RexSnapshot(connection: .connected, reports: [report("child", .done, .pi, child: true)])).completed.isEmpty)
    }

    func testDetailsCloseWhenWorkEndsOrNotificationArrives() {
        let presenter = BannerPresenter()
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .working)]))
        presenter.agentDetailHovered = true
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .done)]))
        XCTAssertFalse(presenter.agentDetailHovered)
        presenter.agentDetailHovered = true
        presenter.present(PulauNotification(app: "App", title: "Notification", body: ""))
        XCTAssertFalse(presenter.agentDetailHovered)
    }

    func testNotificationPriorityAndRemainingWork() {
        let presenter = BannerPresenter()
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .working), report("b", .working, .codex)]))
        XCTAssertEqual(presenter.agentActivity?.stage, .working)
        presenter.present(PulauNotification(app: "App", title: "Notification", body: ""))
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .done), report("b", .working, .codex)]))
        XCTAssertEqual(presenter.agentActivity?.stage, .working)
        presenter.clear()
        XCTAssertEqual(presenter.agentActivity?.stage, .done)
        presenter.finishAgentDone()
        XCTAssertEqual(presenter.agentActivity?.stage, .working)
        XCTAssertEqual(presenter.agentActivity?.label, "Cx")
    }

    func testLiveActivityEventsWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let session = env["PULAU_TEST_REX_SESSION"], let block = env["PULAU_TEST_REX_BLOCK"] else {
            throw XCTSkip("Live activity event test not requested")
        }
        let store = RexAgentStore()
        let presenter = BannerPresenter()
        let snapshotSubscription = store.$snapshot.sink { presenter.updateAgentActivity($0) }
        let eventSubscription = store.$activityEvent.compactMap { $0 }.sink { presenter.updateAgentActivity(event: $0) }
        defer { snapshotSubscription.cancel(); eventSubscription.cancel() }
        let prefix = "\(session)|\(block)|pulau-subagents/"
        for _ in 0..<60 {
            if store.snapshot.reports.contains(where: { ($0.identity?.hasPrefix(prefix) ?? false) && $0.state == .working }) { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertTrue(store.snapshot.reports.contains { ($0.identity?.hasPrefix(prefix) ?? false) && $0.state == .working })
        let executable = try XCTUnwrap(RexClient.executable)
        let result = await Task.detached { RexClient.run(executable, ["send", "-s", session, "-b", block, "d"]) }.value
        XCTAssertNotNil(result)
        for _ in 0..<40 {
            if presenter.agentActivity?.stage == .done { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(presenter.agentActivity?.stage, .done)
    }

    func testNewWorkCancelsStaleDone() {
        let presenter = BannerPresenter()
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .working)]))
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .done)]))
        XCTAssertEqual(presenter.agentActivity?.stage, .done)
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .working)]))
        XCTAssertEqual(presenter.agentActivity?.stage, .working)
        presenter.finishAgentDone()
        XCTAssertEqual(presenter.agentActivity?.stage, .working)
    }

    func testDoneIsReplayedWhenNotificationInterrupts() {
        let presenter = BannerPresenter()
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .working, .pi, child: true)]))
        presenter.updateAgentActivity(RexSnapshot(connection: .connected, reports: [report("a", .done, .pi, child: true)]))
        XCTAssertEqual(presenter.agentActivity?.stage, .done)
        presenter.present(PulauNotification(app: "App", title: "Notification", body: ""))
        presenter.clear()
        XCTAssertEqual(presenter.agentActivity?.stage, .done)
        presenter.finishAgentDone()
        XCTAssertNil(presenter.agentActivity)
    }
}
