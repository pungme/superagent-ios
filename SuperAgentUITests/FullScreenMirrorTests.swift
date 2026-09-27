import XCTest

/// The page full screen, like a stream: it fills the phone, the conversation
/// floats over it, the composer stays, and one tap brings everything back.
final class FullScreenMirrorTests: XCTestCase {
    func testThePageGoesFullScreenWithTheChatFloatingOverIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-withPage", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let open = app.buttons["Open full screen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the docked page offers full screen")
        open.tap()

        let floating = app.buttons["floatingChat"]
        XCTAssertTrue(floating.waitForExistence(timeout: 5), "the conversation floats over the page")
        XCTAssertTrue((floating.value as? String ?? "").hasPrefix("Narrow, the headline holds"))
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "no navigation bar over it")
        let field = app.textFields["Message Claude…"].exists
            ? app.textFields["Message Claude…"]
            : app.textViews.firstMatch
        XCTAssertTrue(field.exists, "you can still write")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "full-screen"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Exit full screen"].tap()
        XCTAssertTrue(floating.waitForNonExistence(timeout: 5), "back to the conversation")
        let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.isHittable, "the messages are back")
    }
}
