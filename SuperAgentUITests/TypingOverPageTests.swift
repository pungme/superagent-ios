import XCTest

/// Typing in a conversation that has a page docked above it, on a phone.
///
/// It used to hide the page when the keyboard came up and keep the messages,
/// which hid the very thing you were writing about. Now the page stays and
/// takes the room; the messages float over it, stream-chat style, and tapping
/// them brings the conversation back. (That used to be a "Show chat" button on
/// the keyboard's toolbar, which crashed on devices when tapped.)
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

        let floating = app.buttons["floatingChat"]
        XCTAssertTrue(floating.waitForExistence(timeout: 5), "the conversation floats over the page")
        XCTAssertEqual(floating.label, "Show chat", "and says what tapping it does")
        XCTAssertTrue(closePage.exists, "the page stays while typing")
        // The transcript's copy of the message, not the floating chat's.
        let inTranscript = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'"))
            .allElementsBoundByIndex
            .filter { !floating.frame.contains($0.frame) && $0.isHittable }
        XCTAssertTrue(inTranscript.isEmpty, "the messages step aside")
        XCTAssertTrue((floating.value as? String ?? "").hasPrefix("Narrow, the headline holds"),
                      "with the newest message in it")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "typing-over-page"
        shot.lifetime = .keepAlways
        add(shot)

        floating.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.isHittable, "the messages come back")
        XCTAssertTrue(closePage.exists)
    }
}
