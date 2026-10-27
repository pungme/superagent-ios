import XCTest

/// A conversation that froze the app is opened lighter next time, and says so.
final class SafeModeTests: XCTestCase {
    func testAConversationThatFrozeTheAppOpensLighterAndCanBeShownInFull() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-hangChat", "c1"]
        app.launch()
        let banner = app.staticTexts["This conversation froze the app last time, so only the latest messages are shown."]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "a conversation that froze the app says it is showing less")
        app.buttons["Show all"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5), "Show all puts it away")
    }

    func testAnOrdinaryConversationHasNoBanner() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c2"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10) || app.staticTexts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["This conversation froze the app last time, so only the latest messages are shown."].exists)
    }
}
