import Combine
import Darwin
import Foundation

enum PiPluginError: LocalizedError {
    case conflictingFiles, commandFailed, commandTimedOut, notInstalled, filtered
    case preferenceBusy, restoreFailed, unsupportedSource, incompleteFiles, multipleInstalls, duplicateInstall

    var errorDescription: String? {
        switch self {
        case .conflictingFiles: return "Install directory already has plugin files. They were not overwritten."
        case .commandFailed: return "Pi command failed. Check Pi is installed and try again."
        case .commandTimedOut: return "Pi command timed out."
        case .notInstalled: return "Pi plugin is not installed."
        case .filtered: return "Pi config filters this plugin. Change that filter in pi config."
        case .preferenceBusy: return "Another Pulau plugin change is in progress. Try again."
        case .restoreFailed: return "Uninstall failed and reporting could not be restored. Check the plugin switch."
        case .unsupportedSource: return "This plugin uses a non-local Pi source. Manage it in pi config."
        case .incompleteFiles: return "Pi plugin files are missing. Uninstall and reinstall the plugin."
        case .multipleInstalls: return "Multiple Pi plugin registrations found. Clean up in pi config first."
        case .duplicateInstall: return "A Pi plugin registration already exists."
        }
    }
}

struct PiPluginStatus {
    let source: URL?
    let enabled: Bool
    let piFiltered: Bool
    let filesAvailable: Bool
}

/// Manages the bundled Pi subagent extension: registration via the official Pi CLI,
/// a Pulau-owned enable preference, and safe rollback on failure.
struct PiPluginService {
    let home: URL
    let agentDirectory: URL
    let preference: URL
    let installDirectory: URL
    let bundledPlugin: URL?
    let piExecutable: URL?

    static func standard() -> PiPluginService {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agent = home.appendingPathComponent(".pi/agent", isDirectory: true)
        let executable = findPi(agentDirectory: agent, path: ProcessInfo.processInfo.environment["PATH"] ?? "")
        let bundled = Bundle.module.url(forResource: "PiSubagents", withExtension: nil)
        return PiPluginService(home: home, agentDirectory: agent,
                               preference: home.appendingPathComponent(".config/pulau/pi-subagents.json"),
                               installDirectory: home.appendingPathComponent("Library/Application Support/Pulau/PiSubagents"),
                               bundledPlugin: bundled, piExecutable: executable)
    }

    /// Pi resolution: agent-local bin first, then PATH, then common fixed locations.
    static func findPi(agentDirectory: URL, path: String) -> URL? {
        let candidates = [agentDirectory.appendingPathComponent("bin/pi")]
            + path.split(separator: ":").filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: String($0)).appendingPathComponent("pi") }
            + [URL(fileURLWithPath: "/opt/homebrew/bin/pi"), URL(fileURLWithPath: "/usr/local/bin/pi")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: Status

    func status() throws -> PiPluginStatus {
        let settings = agentDirectory.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settings)
        let object = try XCTCast.jsonObject(data)
        var matches: [(URL, Bool)] = []
        if let packages = object["packages"] as? [Any] {
            for entry in packages {
                guard let source = (entry as? String) ?? (entry as? [String: Any])?["source"] as? String else { continue }
                if source.hasPrefix("npm:") || source.hasPrefix("git:") || source.contains("://") {
                    if source.lowercased().contains("pulau-pi-subagents") { throw PiPluginError.unsupportedSource }
                    continue
                }
                let url = URL(fileURLWithPath: source, relativeTo: agentDirectory)
                if isPulauPlugin(at: url) {
                    matches.append((url.standardizedFileURL.resolvingSymlinksInPath(),
                                    (entry as? [String: Any])?["extensions"] != nil))
                }
            }
        }
        guard matches.count <= 1 else { throw PiPluginError.multipleInstalls }
        let source = matches.first?.0
        let available = source.map { directory in
            ["index.ts", "reporter.ts", "config.ts"].allSatisfy {
                FileManager.default.isReadableFile(atPath: directory.appendingPathComponent($0).path)
            }
        } ?? false
        return PiPluginStatus(source: source, enabled: try preferenceEnabled(), piFiltered: matches.first?.1 ?? false,
                              filesAvailable: available)
    }

    /// The registered directory is ours when its basename is PiSubagents and, when readable,
    /// its manifest names the Pulau plugin.
    private func isPulauPlugin(at url: URL) -> Bool {
        guard url.lastPathComponent == "PiSubagents" else { return false }
        let manifest = url.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? XCTCast.jsonObject(data),
              let name = object["name"] as? String else { return true }
        return name == "pulau-pi-subagents"
    }

    func preferenceEnabled() throws -> Bool {
        let path = preference.path
        guard FileManager.default.fileExists(atPath: path) else { return true }
        let object = try XCTCast.jsonObject(try Data(contentsOf: preference))
        guard let enabled = object["enabled"] as? Bool else { throw PiPluginError.filtered }
        return enabled
    }

    // MARK: Mutations

    func setEnabled(_ enabled: Bool) throws {
        try withMutationLock {
            let current = try status()
            guard current.source != nil else { throw PiPluginError.notInstalled }
            guard current.filesAvailable else { throw PiPluginError.incompleteFiles }
            guard !current.piFiltered else { throw PiPluginError.filtered }
            try writeEnabled(enabled)
        }
    }

    func install() throws {
        try withMutationLock { try installLocked() }
    }

    private func installLocked() throws {
        let current = try status()
        if let source = current.source {
            throw current.filesAvailable ? PiPluginError.duplicateInstall : PiPluginError.incompleteFiles
        }
        guard let bundledPlugin else { throw PiPluginError.commandFailed }
        let contents = try FileManager.default.contentsOfDirectory(at: bundledPlugin, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != String(".DS_Store") }
        try FileManager.default.createDirectory(at: installDirectory.deletingLastPathComponent(),
                                                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        if FileManager.default.fileExists(atPath: installDirectory.path) {
            let existing = try? FileManager.default.contentsOfDirectory(at: installDirectory, includingPropertiesForKeys: nil)
            if existing?.isEmpty == false { throw PiPluginError.conflictingFiles }
        } else {
            try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        }
        for file in contents {
            try FileManager.default.copyItem(at: file, to: installDirectory.appendingPathComponent(file.lastPathComponent))
        }
        try runPi(["install", installDirectory.path, "--no-approve"])
        guard try status().source != nil else { throw PiPluginError.commandFailed }
    }

    func uninstall() throws {
        try withMutationLock {
            let before = try status()
            guard let source = before.source else { throw PiPluginError.notInstalled }
            try writeEnabled(false)
            do {
                try runPi(["remove", source.path, "--no-approve"])
                guard try status().source == nil else { throw PiPluginError.commandFailed }
            } catch {
                if before.enabled, let current = try? status(), current.source == source, !current.enabled {
                    do { try writeEnabled(true) } catch { throw PiPluginError.restoreFailed }
                }
                throw error
            }
        }
    }

    /// Preserves unrelated preference keys; atomic replace under an advisory lock.
    private func writeEnabled(_ enabled: Bool) throws {
        var object: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: preference.path) {
            object = try XCTCast.jsonObject(try Data(contentsOf: preference))
            guard object["enabled"] == nil || object["enabled"] is Bool else { throw PiPluginError.filtered }
        }
        object["enabled"] = enabled
        let directory = preference.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        try JSONSerialization.data(withJSONObject: object).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(preference, withItemAt: temporary)
    }

    /// Advisory lock so concurrent Pulau mutations serialize instead of overwriting each other.
    private func withMutationLock<T>(_ operation: () throws -> T) throws -> T {
        let directory = preference.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(preference.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw PiPluginError.preferenceBusy }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw PiPluginError.preferenceBusy }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }

    @discardableResult
    private func runPi(_ arguments: [String]) throws -> Data {
        guard let piExecutable else { throw PiPluginError.commandFailed }
        let process = Process()
        let output = Pipe()
        process.executableURL = piExecutable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PI_OFFLINE"] = "1"
        environment["HOME"] = home.path
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw PiPluginError.commandFailed }
        let deadline = Date().addingTimeInterval(60)
        var data = Data()
        let handle = output.fileHandleForReading
        while process.isRunning {
            if let chunk = try? handle.readData(ofLength: 65_536), !chunk.isEmpty { data.append(chunk) }
            if Date() > deadline {
                process.terminate()
                if process.isRunning { usleep(200_000); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
                throw PiPluginError.commandTimedOut
            }
            usleep(50_000)
        }
        data.append(handle.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { throw PiPluginError.commandFailed }
        return data
    }
}

/// JSON object decoding helper that fails closed on anything but a dictionary.
enum XCTCast {
    static func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { throw PiPluginError.filtered }
        return dictionary
    }
}

/// Observable facade for the menu and settings surfaces.
@MainActor
final class PiPluginManager: ObservableObject {
    @Published private(set) var status: PiPluginStatus?
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    private let service = PiPluginService.standard()

    func refresh() {
        status = try? service.status()
    }

    func setEnabled(_ enabled: Bool) {
        run("Turning Pi plugin \(enabled ? "on" : "off")…") { try self.service.setEnabled(enabled) }
    }

    func install() {
        run("Installing Pi plugin…") { try self.service.install() }
    }

    func uninstall() {
        run("Uninstalling Pi plugin…") { try self.service.uninstall() }
    }

    private func run(_ label: String, operation: @escaping @Sendable () throws -> Void) {
        guard !busy else { return }
        busy = true
        message = label
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try operation()
                await MainActor.run {
                    self?.refresh()
                    self?.message = nil
                }
            } catch {
                await MainActor.run {
                    self?.refresh()
                    self?.message = error.localizedDescription
                }
            }
            await MainActor.run { self?.busy = false }
        }
    }
}
