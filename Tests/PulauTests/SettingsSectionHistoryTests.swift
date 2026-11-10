import XCTest
@testable import Pulau

final class SettingsSectionHistoryTests: XCTestCase {
    func testBackForwardAndBranching() {
        var history = SettingsSectionHistory()
        XCTAssertEqual(history.current, .island)
        XCTAssertFalse(history.canGoBack)

        history.select(.notifications)
        history.select(.agents)
        XCTAssertEqual(history.current, .agents)
        XCTAssertTrue(history.canGoBack)
        history.goBack()
        XCTAssertEqual(history.current, .notifications)
        XCTAssertTrue(history.canGoForward)

        history.select(.piSubagents)
        XCTAssertFalse(history.canGoForward)
        history.goBack()
        XCTAssertEqual(history.current, .notifications)
        history.goForward()
        XCTAssertEqual(history.current, .piSubagents)
    }
}
