import AppKit
import XCTest
@testable import Pulau

@MainActor
final class SystemBackdropTests: XCTestCase {
    func testMaterialIsSupportedOrFallsBack() {
        let view = SystemBackdrop.makeBackdrop()
        XCTAssertEqual(view.material, .hudWindow)
        XCTAssertEqual(view.blendingMode, .behindWindow)
    }

    func testExperimentalBackdropLayout() {
        let view = PrivateGlassContainer(frame: NSRect(x: 0, y: 0, width: 360, height: 174))
        view.layout()
        XCTAssertEqual(view.subviews.count, 2)
        XCTAssertEqual(view.subviews[0].frame, view.bounds)
        XCTAssertEqual(view.subviews[1].frame, view.bounds)
        let overlay = view.subviews[1] as? PrivateGlassBlackOverlay
        XCTAssertNotNil(overlay?.shape)
        if #available(macOS 26.0, *), PrivateGlassContainer.supportsPrivateGlass(ProcessInfo.processInfo.operatingSystemVersion),
           let glass = view.subviews[0] as? NSGlassEffectView {
            XCTAssertEqual(glass.value(forKey: "_variant") as? Int, 11)
        }
    }

    func testExperimentalHoverBackdropUsesRoundedShape() {
        let view = PrivateGlassContainer(frame: NSRect(x: 0, y: 0, width: 320, height: 190))
        view.rounded = true
        view.layout()
        let overlay = view.subviews[1] as? PrivateGlassBlackOverlay
        XCTAssertNotNil(overlay?.shape)
        XCTAssertFalse(overlay?.shape?.contains(CGPoint(x: 1, y: 1)) ?? true)
        XCTAssertTrue(overlay?.shape?.contains(CGPoint(x: 160, y: 95)) ?? false)
        view.rounded = false
        view.layout()
        XCTAssertTrue(overlay?.shape?.contains(CGPoint(x: 10, y: 1)) ?? false)
    }

    func testExperimentalHoverBackdropDrawsTailInsideBounds() {
        let view = PrivateGlassContainer(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        view.tailX = 160
        view.layout()
        let overlay = view.subviews[1] as? PrivateGlassBlackOverlay
        let shape = try? XCTUnwrap(overlay?.shape)
        XCTAssertFalse(try XCTUnwrap(shape).contains(CGPoint(x: 1, y: 199)))
        XCTAssertTrue(try XCTUnwrap(shape).contains(CGPoint(x: 160, y: 1)))
        XCTAssertTrue(try XCTUnwrap(shape).contains(CGPoint(x: 160, y: 120)))
    }

    func testPrivateGlassVersionGate() {
        XCTAssertTrue(PrivateGlassContainer.supportsPrivateGlass(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)))
        XCTAssertFalse(PrivateGlassContainer.supportsPrivateGlass(OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0)))
        XCTAssertFalse(PrivateGlassContainer.supportsPrivateGlass(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)))
    }
}
