import Foundation
import XCTest
@testable import Pulau

final class IslandPreferencesTests: XCTestCase {
    func testSettingsPersistAcrossInstances() throws {
        let suite = "PulauTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = IslandPreferences(defaults: defaults)
        XCTAssertFalse(preferences.notificationsEnabled)
        XCTAssertEqual(preferences.look, .glassy)
        XCTAssertEqual(preferences.expandPreference, .default)
        preferences.expandPreference = .minimal
        preferences.notificationsEnabled = true
        preferences.look = .solid
        let reloaded = IslandPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.notificationsEnabled)
        XCTAssertEqual(reloaded.look, .solid)
        XCTAssertEqual(reloaded.expandPreference, .minimal)
        reloaded.notificationsEnabled = false
        reloaded.look = .systemExperimental
        XCTAssertEqual(preferences.look, .systemExperimental)
        reloaded.look = .glassy
        XCTAssertFalse(preferences.notificationsEnabled)
        XCTAssertEqual(preferences.look, .glassy)
    }
}
