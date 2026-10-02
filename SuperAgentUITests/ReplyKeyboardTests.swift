import XCTest

/// Reply, from a message's hold menu, with the keyboard coming up.
///
/// Reply focuses the composer for you, so the keyboard arrives without a tap on
/// the field. When the conversation made no room for it, it came up over the
/// composer and the quote, and you typed a reply you could not see. That
/// happened whenever iOS reported a hardware keyboard that was not really
/// there (see KeyboardRoom); the plain cases are pinned here too.
final class ReplyKeyboardTests: XCTestCase {
    private func open(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"] + extra
        app.launch()
        return app
    }

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["Message Claude…"].exists ? app.textFields["Message Claude…"] : app.textViews.firstMatch
    }

    private func reply(to message: XCUIElement, in app: XCUIApplication) throws {
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        message.press(forDuration: 1.0)
        let reply = app.buttons["Reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "the hold menu offers Reply")
        reply.tap()

        let cancel = app.buttons["Cancel reply"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "the quote sits above the composer")
        let keyboard = app.keyboards.firstMatch
        // A simulator with "Connect Hardware Keyboard" on never shows one, and
        // then there is nothing to be covered by.
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("no on-screen keyboard on this simulator")
        }
        // Let the keyboard and the menu both finish moving.
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reply-keyboard"
        shot.lifetime = .keepAlways
        add(shot)

        let top = keyboard.frame.minY
        let field = composer(app)
        XCTAssertLessThanOrEqual(field.frame.maxY, top + 1, "the composer sits above the keyboard, not under it")
        XCTAssertLessThanOrEqual(cancel.frame.maxY, top + 1, "and so does the quote")
        XCTAssertTrue(field.isHittable, "you can see what you type")
    }

    func testReplyingToTheAgentKeepsTheComposerAboveTheKeyboard() throws {
        let app = open()
        try reply(to: app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'")).firstMatch,
                  in: app)
    }

    func testReplyingToYourOwnMessageKeepsTheComposerAboveTheKeyboard() throws {
        let app = open()
        try reply(to: app.staticTexts["Better. Now check it on a phone."], in: app)
    }

    /// A real conversation is far taller than the screen, and its messages
    /// are far taller than the harness's two-liners.
    func testReplyingInALongConversationKeepsTheComposerAboveTheKeyboard() throws {
        let app = open(["-longTranscript"])
        try reply(to: app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Have a look in the pane'")).firstMatch,
                  in: app)
    }

    /// GameController reports a hardware keyboard that is not really there (a
    /// phone Xcode has lent one to does), and the on-screen keyboard comes up
    /// all the same. The conversation used to take the report at its word and
    /// make no room at all.
    func testAKeyboardThatIsOnlyClaimedStillLeavesTheComposerInView() throws {
        let app = open(["-hardwareKeyboard"])
        try reply(to: app.staticTexts["Better. Now check it on a phone."], in: app)
    }

    func testTypingWithAClaimedKeyboardLeavesTheComposerInView() throws {
        let app = open(["-hardwareKeyboard"])
        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("no on-screen keyboard on this simulator")
        }
        sleep(1)
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY + 1, "the composer sits above the keyboard")
        XCTAssertTrue(field.isHittable)
    }
}
