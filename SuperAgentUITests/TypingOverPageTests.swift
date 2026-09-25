import XCTest

/// Typing in a conversation that has a page docked above it, on a phone.
///
/// It used to hide the page when the keyboard came up and keep the messages,
/// which hid the very thing you were writing about. Now the page stays and
/// takes the room; the messages step aside until you're done, and the
/// keyboard's toolbar offers the way back.
final class TypingOverPageTests: XCTestCase {
    func testThePageStaysWhileYouType() {
        let app = XCUIApplication()
        // A conversation with a page open on the Mac, straight in.
        app.launchArguments = ["-sidebarHarness", "-withPage", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let closePage = app.buttons["Close the page"]
        XCTAssertTrue(closePage.waitForExistence(timeout: 10), "the page is docked above the chat")
        // The newest message: the one on screen when the chat is at its end.
        let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "the conversation shows")
        XCTAssertTrue(message.isHittable, "the newest message is on screen")

        let field = app.textFields["Message Claude…"].exists
            ? app.textFields["Message Claude…"]
            : app.textViews.firstMatch
        field.tap()

        XCTAssertTrue(app.buttons["Show chat"].waitForExistence(timeout: 5), "the keyboard offers the way back")
        XCTAssertTrue(closePage.exists, "the page stays while typing")
        XCTAssertFalse(message.isHittable, "the messages step aside")

        app.buttons["Show chat"].tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.isHittable, "the messages come back")
        XCTAssertTrue(closePage.exists)
    }
}
