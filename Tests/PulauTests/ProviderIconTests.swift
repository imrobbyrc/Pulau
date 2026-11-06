import AppKit
import XCTest
@testable import Pulau

final class ProviderIconTests: XCTestCase {
    func testBundledProviderIconsLoad() throws {
        for name in ["codex", "zai"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "ProviderIcons"))
            XCTAssertNotNil(NSImage(contentsOf: url))
        }
    }
}
