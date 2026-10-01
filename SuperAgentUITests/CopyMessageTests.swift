import XCTest

/// Holding a message offers Copy. It only offered Reply, and the hold menu
/// takes the long press text selection would have had — so there was no way to
/// copy anything out of a conversation.
///
/// What lands on the clipboard is checked from the Mac (`simctl pbpaste`): iOS
/// does not let the test runner read another app's pasteboard.
final class CopyMessageTests: XCTestCase {
    private func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()
        return app
    }

    func testCopyingTheAgentsMessage() {
        let app = open()
        let msg = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'")).firstMatch
        XCTAssertTrue(msg.waitForExistence(timeout: 10))
        msg.press(forDuration: 1.0)
        let copy = app.buttons["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "the hold menu offers Copy")
        XCTAssertTrue(app.buttons["Reply"].exists, "alongside Reply")
        copy.tap()
        XCTAssertFalse(copy.waitForExistence(timeout: 2), "and the menu closes")
    }

    func testCopyingYourOwnMessage() {
        let app = open()
        let msg = app.staticTexts["Better. Now check it on a phone."]
        XCTAssertTrue(msg.waitForExistence(timeout: 10))
        msg.press(forDuration: 1.0)
        let copy = app.buttons["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertFalse(copy.waitForExistence(timeout: 2))
    }
}
