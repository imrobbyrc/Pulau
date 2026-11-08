import AppKit
import Foundation

/// Stores and resolves the user's custom working-buddy asset (image or GIF).
struct BuddyStore {
    let defaults: UserDefaults
    let directory: URL

    init(defaults: UserDefaults, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Pulau/Buddies", isDirectory: true)
    }

    var usesCustom: Bool {
        get { defaults.bool(forKey: "buddyUsesCustom") }
        nonmutating set { defaults.set(newValue, forKey: "buddyUsesCustom") }
    }

    var assetName: String? {
        get { defaults.string(forKey: "buddyAssetName") }
        nonmutating set { defaults.set(newValue, forKey: "buddyAssetName") }
    }

    /// The custom image when enabled and readable; otherwise nil (built-in eyes).
    func resolve() -> NSImage? {
        guard usesCustom, let name = assetName else { return nil }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Copies the picked asset into the buddy directory and enables it.
    /// Returns the stored file name.
    @discardableResult
    func adopt(_ url: URL) throws -> String {
        let supported = ["png", "jpg", "jpeg", "gif", "tiff", "heic"]
        guard supported.contains(url.pathExtension.lowercased()) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type. Use PNG, JPG, GIF, TIFF, or HEIC."])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        var name = url.lastPathComponent
        var destination = directory.appendingPathComponent(name)
        var attempt = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            attempt += 1
            name = "\(url.deletingPathExtension().lastPathComponent)-\(attempt).\(url.pathExtension)"
            destination = directory.appendingPathComponent(name)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        assetName = name
        usesCustom = true
        return name
    }

    /// Reverts to the built-in eyes; the stored file is kept for later.
    func reset() {
        usesCustom = false
    }
}
