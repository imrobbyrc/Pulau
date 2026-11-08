import XCTest
@testable import Pulau

final class QuotaThresholdTrackerTests: XCTestCase {
    func testCrossingsAreIndependentAndSurviveRelaunch() throws {
        let name = "QuotaThresholdTrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = QuotaThresholdTracker(defaults: defaults)
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: 65))
        XCTAssertNil(tracker.crossedThreshold(for: .codex, remaining: 80))
        XCTAssertEqual(tracker.crossedThreshold(for: .glm, remaining: 50), 50)
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: 49))
        XCTAssertEqual(QuotaThresholdTracker(defaults: defaults).crossedThreshold(for: .glm, remaining: 9), 10)
        XCTAssertEqual(tracker.crossedThreshold(for: .glm, remaining: 0), 0)
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: 0))
        XCTAssertEqual(tracker.crossedThreshold(for: .codex, remaining: 29), 30)
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: 100))
        XCTAssertEqual(tracker.crossedThreshold(for: .glm, remaining: 50), 50)
        tracker.reset(.glm)
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: 10))
    }

    func testInvalidReadingsDoNotChangeBaseline() throws {
        let name = "QuotaThresholdTrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = QuotaThresholdTracker(defaults: defaults)
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: 60))
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: .nan))
        XCTAssertNil(tracker.crossedThreshold(for: .glm, remaining: -1))
        XCTAssertEqual(tracker.crossedThreshold(for: .glm, remaining: 30), 30)
    }
}
