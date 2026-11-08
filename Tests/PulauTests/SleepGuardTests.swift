import Foundation
import XCTest
@testable import Pulau

@MainActor
final class SleepGuardTests: XCTestCase {
    private func makeGuard(_ defaults: UserDefaults, now: Date) -> (SleepGuard, () -> Date, [Bool]) {
        let clock = { now }
        var assertions: [Bool] = []
        let guardObject = SleepGuard(preferences: AgentAwakePreferences(defaults: defaults),
                                     clock: clock, preventSleep: { assertions.append($0) })
        return (guardObject, clock, assertions)
    }

    private func snapshot(_ states: [RexAgentState], connection: RexSnapshot.Connection = .connected) -> RexSnapshot {
        RexSnapshot(connection: connection, reports: states.enumerated().map {
            RexAgentReport(agent: .pi, state: $1, identity: "\($0)")
        })
    }

    func testPreventsWhileWorkingAndReleasesAfterIdleDelay() {
        let suite = "PulauTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "agentAwakeEnabled")
        var now = Date()
        var assertions: [Bool] = []
        let guardObject = SleepGuard(preferences: AgentAwakePreferences(defaults: defaults),
                                     clock: { now }, preventSleep: { assertions.append($0) })
        XCTAssertEqual(guardObject.idleMinutes, 2)

        guardObject.update(snapshot: snapshot([.working]))
        XCTAssertTrue(guardObject.preventingSleep)
        XCTAssertEqual(assertions, [true])

        now += 119
        guardObject.evaluate()
        XCTAssertTrue(guardObject.preventingSleep)

        now += 2
        guardObject.update(snapshot: snapshot([]))
        guardObject.evaluate()
        XCTAssertFalse(guardObject.preventingSleep)
        XCTAssertEqual(assertions, [true, false])
    }

    func testNewWorkingResetsIdleTimerAndOfflineReleases() {
        let suite = "PulauTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "agentAwakeEnabled")
        var now = Date()
        var assertions: [Bool] = []
        let guardObject = SleepGuard(preferences: AgentAwakePreferences(defaults: defaults),
                                     clock: { now }, preventSleep: { assertions.append($0) })
        guardObject.update(snapshot: snapshot([.working]))
        now += 110
        guardObject.update(snapshot: snapshot([.done, .working]))
        now += 110
        guardObject.evaluate()
        XCTAssertTrue(guardObject.preventingSleep)
        now += 2
        guardObject.update(snapshot: .offline)
        XCTAssertFalse(guardObject.preventingSleep)
        XCTAssertEqual(assertions, [true, false])
    }

    func testDisableReleasesImmediatelyAndSettingsPersist() {
        let suite = "PulauTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "agentAwakeEnabled")
        var now = Date()
        var assertions: [Bool] = []
        let guardObject = SleepGuard(preferences: AgentAwakePreferences(defaults: defaults),
                                     clock: { now }, preventSleep: { assertions.append($0) })
        guardObject.update(snapshot: snapshot([.working]))
        XCTAssertTrue(guardObject.preventingSleep)
        guardObject.isEnabled = false
        XCTAssertFalse(guardObject.preventingSleep)
        XCTAssertEqual(assertions, [true, false])
        guardObject.idleMinutes = 7
        XCTAssertEqual(guardObject.idleMinutes, 5)

        let reloaded = SleepGuard(preferences: AgentAwakePreferences(defaults: defaults),
                                  clock: { now }, preventSleep: { assertions.append($0) })
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.idleMinutes, 5)
    }
}
