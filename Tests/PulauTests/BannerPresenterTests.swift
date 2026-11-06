import XCTest
@testable import Pulau

@MainActor
final class BannerPresenterTests: XCTestCase {
    func testHoverAndNotificationTransitions() {
        let presenter = BannerPresenter()
        presenter.setHovered(true)
        XCTAssertEqual(presenter.state, .full)
        presenter.setHovered(false)
        XCTAssertEqual(presenter.state, .collapsed)

        presenter.expandPreference = .minimal
        presenter.setHovered(true)
        XCTAssertEqual(presenter.state, .minimal)
        presenter.expandFromView()
        XCTAssertEqual(presenter.state, .full)
        presenter.setHovered(false)
        XCTAssertEqual(presenter.state, .collapsed)

        presenter.present(PulauNotification(app: "App", title: "Title", body: "Body"))
        presenter.expandFromView()
        presenter.setHovered(true)
        XCTAssertEqual(presenter.state, .full)
        presenter.dismiss()
        presenter.clear()
        XCTAssertEqual(presenter.state, .minimal)
        presenter.expandPreference = .default
        XCTAssertEqual(presenter.state, .full)
    }
}
