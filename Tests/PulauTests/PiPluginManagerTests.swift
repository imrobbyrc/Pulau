import XCTest
import Darwin
@testable import Pulau

final class PiPluginManagerTests: XCTestCase {
    private func sandbox() throws -> (URL, PiPluginService) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("pulau-pi-test-\(UUID().uuidString)", isDirectory: true)
        let agent = home.appendingPathComponent(".pi/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = project.appendingPathComponent("Integrations/PiSubagents", isDirectory: true)
        let pi = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/bin/pi")
        return (home, PiPluginService(home: home, agentDirectory: agent,
                                      preference: home.appendingPathComponent(".config/pulau/pi-subagents.json"),
                                      installDirectory: home.appendingPathComponent("Library/Application Support/Pulau/PiSubagents"),
                                      bundledPlugin: bundle, piExecutable: pi))
    }

    func testTogglePreservesPiSettingsAndOtherPreferences() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try XCTUnwrap(service.bundledPlugin)
        let settings = service.agentDirectory.appendingPathComponent("settings.json")
        let data = try JSONSerialization.data(withJSONObject: ["packages": [source.path], "unrelated": ["keep": true]])
        try data.write(to: settings)
        try FileManager.default.createDirectory(at: service.preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"enabled":true,"future":"keep"}"#.utf8).write(to: service.preference)
        XCTAssertTrue(try service.status().enabled)
        try service.setEnabled(false)
        XCTAssertFalse(try service.status().enabled)
        XCTAssertEqual(try Data(contentsOf: settings), data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: service.preference)) as? [String: Any])
        XCTAssertEqual(object["future"] as? String, "keep")
        try service.setEnabled(true)
        XCTAssertTrue(try service.status().enabled)
    }

    func testInvalidFilesAndPiFiltersAreNeverOverwritten() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try XCTUnwrap(service.bundledPlugin)
        let settings = service.agentDirectory.appendingPathComponent("settings.json")
        let filtered = try JSONSerialization.data(withJSONObject: ["packages": [["source": source.path, "extensions": []]]])
        try filtered.write(to: settings)
        XCTAssertTrue(try service.status().piFiltered)
        XCTAssertThrowsError(try service.setEnabled(false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.preference.path))
        try Data("{".utf8).write(to: settings)
        XCTAssertThrowsError(try service.status())
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "{")
    }

    func testInvalidPreferenceFailsClosedWithoutReplacingIt() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try XCTUnwrap(service.bundledPlugin)
        try JSONSerialization.data(withJSONObject: ["packages": [source.path]])
            .write(to: service.agentDirectory.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: service.preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"enabled":"false"}"#.utf8).write(to: service.preference)
        XCTAssertThrowsError(try service.setEnabled(true))
        XCTAssertEqual(try String(contentsOf: service.preference, encoding: .utf8), #"{"enabled":"false"}"#)
    }

    func testRelativePackagePathIsDetected() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent("plugins/PiSubagents", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"name":"pulau-pi-subagents"}"#.utf8).write(to: source.appendingPathComponent("package.json"))
        let settings = service.agentDirectory.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: ["packages": ["../../plugins/PiSubagents"]]).write(to: settings)
        XCTAssertEqual(try service.status().source, source.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertFalse(try service.status().filesAvailable)
        XCTAssertThrowsError(try service.setEnabled(true))
    }

    func testFailedUninstallRestoresEnabledPreference() throws {
        let (home, base) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try XCTUnwrap(base.bundledPlugin)
        let settings = base.agentDirectory.appendingPathComponent("settings.json")
        let original = try JSONSerialization.data(withJSONObject: ["packages": [source.path], "other": "keep"])
        try original.write(to: settings)
        let service = PiPluginService(home: base.home, agentDirectory: base.agentDirectory, preference: base.preference,
                                      installDirectory: base.installDirectory, bundledPlugin: base.bundledPlugin,
                                      piExecutable: URL(fileURLWithPath: "/usr/bin/false"))
        XCTAssertThrowsError(try service.uninstall())
        XCTAssertTrue(try service.status().enabled)
        XCTAssertNotNil(try service.status().source)
        XCTAssertEqual(try Data(contentsOf: settings), original)
    }

    func testConcurrentChangeRefusesRatherThanOverwrites() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try XCTUnwrap(service.bundledPlugin)
        try JSONSerialization.data(withJSONObject: ["packages": [source.path]])
            .write(to: service.agentDirectory.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: service.preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(service.preference.path + ".lock", O_CREAT | O_RDWR, mode_t(0o600))
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        defer { flock(fd, LOCK_UN) }
        XCTAssertThrowsError(try service.setEnabled(false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.preference.path))
    }

    func testFindPiOnCustomPath() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent("custom-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("pi")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        XCTAssertEqual(PiPluginService.findPi(agentDirectory: service.agentDirectory, path: directory.path), executable)
    }

    func testStaleRegistrationAndConflictingFilesAreNotOverwritten() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = service.agentDirectory.appendingPathComponent("settings.json")
        let stale = home.appendingPathComponent("missing/PiSubagents")
        let data = try JSONSerialization.data(withJSONObject: ["packages": [stale.path]])
        try data.write(to: settings)
        XCTAssertThrowsError(try service.install())
        XCTAssertEqual(try Data(contentsOf: settings), data)
        try JSONSerialization.data(withJSONObject: ["packages": []]).write(to: settings)
        try FileManager.default.createDirectory(at: service.installDirectory, withIntermediateDirectories: true)
        let existing = service.installDirectory.appendingPathComponent("index.ts")
        try Data("user changes".utf8).write(to: existing)
        XCTAssertThrowsError(try service.install())
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "user changes")
    }

    func testLivePiPluginRegistrationWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["PULAU_TEST_PI_MANAGER"] == "1" else { throw XCTSkip("Live Pi registration test not requested") }
        XCTAssertNotNil(try PiPluginService.standard().status().source)
    }

    func testInstallAndUninstallOnlyPluginInIsolatedPiConfig() throws {
        let (home, service) = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        guard let pi = service.piExecutable, FileManager.default.isExecutableFile(atPath: pi.path) else { throw XCTSkip("Pi CLI not installed") }
        let other = home.appendingPathComponent("other-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data(#"{"name":"another-plugin"}"#.utf8).write(to: other.appendingPathComponent("package.json"))
        let settings = service.agentDirectory.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: ["packages": [other.path], "defaultThinkingLevel": "low"])
            .write(to: settings)
        try service.install()
        XCTAssertEqual(try service.status().source, service.installDirectory.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertTrue(try service.status().enabled)
        try service.uninstall()
        XCTAssertNil(try service.status().source)
        XCTAssertFalse(try service.preferenceEnabled())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual(object["defaultThinkingLevel"] as? String, "low")
        XCTAssertTrue((object["packages"] as? [String])?.contains(other.path) == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.installDirectory.path))
    }
}
