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

    func testPrivateGlassVersionGate() {
        XCTAssertTrue(PrivateGlassContainer.supportsPrivateGlass(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)))
        XCTAssertFalse(PrivateGlassContainer.supportsPrivateGlass(OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0)))
        XCTAssertFalse(PrivateGlassContainer.supportsPrivateGlass(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)))
    }
}
