import XCTest
@testable import Pulau

@MainActor
final class BannerPresenterTests: XCTestCase {
    func testIslandHeightsKeepExpandedUsageBackgroundTall() {
        XCTAssertEqual(IslandState.full.height(notification: false), 174)
        XCTAssertEqual(IslandState.full.height(notification: true), 84)
        XCTAssertEqual(IslandState.collapsed.height(notification: false), 32)
    }

    func testAlertReturnsToCollapsedIdle() {
        let presenter = BannerPresenter()
        XCTAssertEqual(presenter.state, .collapsed)
        presenter.present(PulauNotification(app: "GLM", title: "5h limit: 30% left", body: ""),
                          quotaAlert: QuotaAlert(provider: .glm, remaining: 30))
        presenter.expandFromView()
        XCTAssertEqual(presenter.state, .full)
        XCTAssertEqual(presenter.quotaAlert?.provider, .glm)
        XCTAssertEqual(presenter.quotaAlert?.remaining, 30)
        presenter.dismiss()
        presenter.clear()
        XCTAssertNil(presenter.quotaAlert)
        XCTAssertNil(presenter.note)
        XCTAssertEqual(presenter.state, .collapsed)
    }

    func testLiquidProgressOpensAndCloses() {
        let duration = QuotaLiquidAlert.duration
        XCTAssertEqual(QuotaLiquidAlert.progress(elapsed: 0, closing: false), 0)
        XCTAssertEqual(QuotaLiquidAlert.progress(elapsed: duration / 2, closing: false), 0.5, accuracy: 0.001)
        XCTAssertEqual(QuotaLiquidAlert.progress(elapsed: duration, closing: false), 1)
        XCTAssertEqual(QuotaLiquidAlert.progress(elapsed: 0, closing: true), 1)
        XCTAssertEqual(QuotaLiquidAlert.progress(elapsed: duration, closing: true), 0)
        XCTAssertEqual(QuotaLiquidAlert.progress(elapsed: duration * 2, closing: true), 0)
    }

    func testApprovedLiquidGeometry() {
        XCTAssertEqual(QuotaLiquidAlert.duration, 2)
        XCTAssertEqual(QuotaLiquidAlert.diameter, 23.04, accuracy: 0.001)
        XCTAssertEqual(QuotaLiquidAlert.spread(0), 0)
        XCTAssertEqual(QuotaLiquidAlert.spread(1), 1)
        for width in [CGFloat(179), 185] {
            let edge = 220 + width / 2
            let mask = QuotaLiquidAlert.outsideNotch(notchWidth: width)
            XCTAssertFalse(mask.contains(CGPoint(x: 220, y: 16), eoFill: true))
            XCTAssertTrue(mask.contains(CGPoint(x: edge - 5, y: 28), eoFill: true))
            XCTAssertTrue(mask.contains(CGPoint(x: 220, y: 40), eoFill: true))
            XCTAssertGreaterThan(QuotaLiquidAlert.bridge(circleX: edge + 5, notchWidth: width).boundingRect.height, 28)
            XCTAssertTrue(QuotaLiquidAlert.bridge(circleX: QuotaLiquidAlert.restingX(notchWidth: width), notchWidth: width).isEmpty)
        }
    }

    func testQuotaAnimatesFromCollapsedEvenWhileHovered() {
        let presenter = BannerPresenter()
        presenter.setHovered(true)
        XCTAssertEqual(presenter.state, .full)
        presenter.present(PulauNotification(app: "GLM", title: "30%", body: ""),
                          quotaAlert: QuotaAlert(provider: .glm, remaining: 30))
        XCTAssertEqual(presenter.state, .collapsed)
        presenter.expandFromView()
        presenter.dismiss()
        XCTAssertEqual(presenter.state, .collapsed)
        presenter.clear()
        XCTAssertEqual(presenter.state, .full)
    }

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
