import XCTest

final class InterfaceTests: XCTestCase {
    func testHistoryNavigationAndFullScreenRoute() {
        let app = launch()
        XCTAssertTrue(app.buttons["行程记录"].waitForExistence(timeout: 15))
        capture("01-home", app: app)
        app.buttons["行程记录"].tap()
        XCTAssertTrue(app.staticTexts["滨海公园"].waitForExistence(timeout: 10))
        capture("02-drives", app: app)
        app.staticTexts["滨海公园"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["行程回顾"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.buttons["全屏查看路线"].waitForExistence(timeout: 5))
        app.buttons["全屏查看路线"].tap()
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 5))
        capture("03-fullscreen-route", app: app)
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["行程详情"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["管理连接"].waitForExistence(timeout: 5))
        capture("04-settings", app: app)
    }

    func testDarkAppearanceAndCharging() {
        let app = launch(extra: ["--ui-dark"])
        XCTAssertTrue(app.buttons["充电记录"].waitForExistence(timeout: 15))
        capture("05-home-dark", app: app)
        app.buttons["充电记录"].tap()
        XCTAssertTrue(app.staticTexts["城市充电站"].waitForExistence(timeout: 10))
        app.staticTexts["城市充电站"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["充电回顾"].waitForExistence(timeout: 10))
        capture("06-charging-dark", app: app)
    }

    func testAccessibilityTextSize() {
        let app = launch(extra: ["--ui-large"])
        XCTAssertTrue(app.staticTexts["我的 Model 3"].waitForExistence(timeout: 15))
        capture("07-large-text", app: app)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["管理连接"].waitForExistence(timeout: 5))
        capture("08-settings-large-text", app: app)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"] + extra
        app.launch()
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
