import AppKit
import XCTest
@testable import Pulau

final class BuddyStoreTests: XCTestCase {
    private func makeStore() throws -> (BuddyStore, URL) {
        let suite = "PulauTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pulau-buddy-\(UUID().uuidString)", isDirectory: true)
        return (BuddyStore(defaults: defaults, directory: directory), directory)
    }

    private func fixtureImage(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
        return url
    }

    func testAdoptCopiesEnablesAndResolveReturnsImage() throws {
        let (store, _) = try makeStore()
        let picked = try fixtureImage("buddy-fixture.png")
        let name = try store.adopt(picked)
        XCTAssertEqual(name, "buddy-fixture.png")
        XCTAssertTrue(store.usesCustom)
        XCTAssertEqual(store.assetName, "buddy-fixture.png")
        let resolved = try XCTUnwrap(store.resolve())
        XCTAssertEqual(resolved.size.width, 4, accuracy: 0.5)
    }

    func testAdoptDeduplicatesNamesAndRejectsUnsupportedFiles() throws {
        let (store, _) = try makeStore()
        let picked = try fixtureImage("buddy.png")
        try store.adopt(picked)
        let second = try store.adopt(picked)
        XCTAssertEqual(second, "buddy-2.png")
        XCTAssertNotEqual(second, "buddy.png")
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("buddy.txt")
        try Data("hi".utf8).write(to: text)
        XCTAssertThrowsError(try store.adopt(text))
        XCTAssertFalse(store.usesCustom ? store.assetName == "buddy.txt" : false)
    }

    func testResetRevertsToEyesButKeepsResolvePathStable() throws {
        let (store, directory) = try makeStore()
        let picked = try fixtureImage("buddy.png")
        try store.adopt(picked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("buddy.png").path))
        store.reset()
        XCTAssertFalse(store.usesCustom)
        XCTAssertNil(store.resolve())
        XCTAssertEqual(store.assetName, "buddy.png")
    }
}
