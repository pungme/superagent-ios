import XCTest

/// A page open on the Mac, in a conversation on a phone: picture in picture.
///
/// It used to dock above the conversation, half a screen for each and enough
/// of neither; and before that, typing hid it. Now the conversation keeps the
/// screen and the page is a small card floating over it, which you can drag to
/// a corner, open full screen, or put away. Typing changes none of that.
final class TypingOverPageTests: XCTestCase {
    /// `corner`: where the picture starts. Given on the command line it is
    /// also where it stays, so the test that moves it passes nil.
    private func launch(_ extra: [String] = ["-withPage"], corner: String? = "topTrailing") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
            + (corner.map { ["-mirror.pip.corner", $0] } ?? []) + [
                               // Shown, whatever an earlier run left: putting a page away is remembered.
                               "-pageHidden:c1", "NO", "-simHidden:c1", "NO"] + extra
        app.launch()
        return app
    }

    func testThePageFloatsOverTheConversationAndStaysWhileYouType() {
        let app = launch()
        let pip = app.buttons["mirror-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10), "the page is a small picture over the chat")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(pip.frame.width, window.width * 0.6, "small, not a strip across the screen")
        XCTAssertGreaterThan(pip.frame.midX, window.midX, "in the top right to begin with")

        // The whole conversation is there, not folded away under a page.
        let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.isHittable, "the newest message is on screen")

        let field = app.textFields["Message Claude…"].exists
            ? app.textFields["Message Claude…"]
            : app.textViews.firstMatch
        field.tap()
        XCTAssertTrue(pip.waitForExistence(timeout: 5), "the page stays while typing")
        XCTAssertTrue(pip.isHittable)
        XCTAssertFalse(app.buttons["floatingChat"].exists, "and the messages are not swapped for floating ones")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "typing-with-pip"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testItCanBeDraggedToAnotherCornerAndPutAway() throws {
        // On an iPad the card sits in the second column, and a synthesised
        // drag there does not move it (a real finger does; see the board).
        // The drag is proved on a phone; the rest of this test holds anywhere.
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let app = launch(corner: nil)
        let pip = app.buttons["mirror-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        // Dragged a long way across, it settles on the other side of its
        // column: the card keeps to the conversation, which on an iPad is the
        // second column, not the whole window. (Wherever it starts: the
        // corner is remembered between runs.)
        let startX = pip.frame.midX
        let column = app.textViews.firstMatch.exists ? app.textViews.firstMatch.frame : app.windows.firstMatch.frame
        let wasRight = startX > column.midX
        if !pad {
            let from = pip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = from.withOffset(CGVector(dx: wasRight ? -(column.width * 0.7) : column.width * 0.7, dy: 0))
            from.press(forDuration: 0.1, thenDragTo: to)
            let settled = expectation(for: NSPredicate { _, _ in abs(pip.frame.midX - startX) > 120 }, evaluatedWith: nil)
            wait(for: [settled], timeout: 5)
            XCTAssertFalse(app.buttons["Exit full screen"].exists, "a drag moves it; it does not open it")
        }

        // The ×: gone, and the conversation says it still has a page.
        app.buttons["Close the page"].tap()
        XCTAssertTrue(pip.waitForNonExistence(timeout: 5))
        let show = app.staticTexts["Show"]
        XCTAssertTrue(show.waitForExistence(timeout: 5), "with a way to bring it back")
        // And back: putting it away is remembered for the conversation, so
        // this also leaves things as the other tests expect to find them.
        show.tap()
        XCTAssertTrue(pip.waitForExistence(timeout: 5))
    }

    func testTheSimulatorIsAPictureToo() {
        let app = launch(["-withSim"])
        let pip = app.buttons["mirror-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(pip.frame.height, pip.frame.width, "tall, like the phone it shows")
        XCTAssertTrue(app.buttons["Close the simulator"].exists)
    }
}
