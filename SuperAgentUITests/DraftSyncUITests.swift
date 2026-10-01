import XCTest

/// What is typed in the Mac's composer shows up in the phone's, and words
/// being typed here are not replaced by the Mac's older copy.
final class DraftSyncUITests: XCTestCase {
    func testTheMacsDraftAppearsAndTypingHereWins() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects", "-macDraft"]
        app.launch()

        // The field is found by its placeholder while empty, and has no
        // such name once it holds words, so take whichever is on screen.
        func composer() -> XCUIElement {
            app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        }
        XCTAssertTrue(app.staticTexts["Better. Now check it on a phone."].waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(10)
        while composer().value as? String != "started on the Mac", Date() < deadline { usleep(200_000) }
        let field = composer()
        XCTAssertEqual(field.value as? String, "started on the Mac")

        // Past the end of the words, where a thumb goes to carry on typing.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        field.typeText(" and finished here")
        XCTAssertEqual(composer().value as? String, "started on the Mac and finished here")

        // The harness reports different words from the Mac ten seconds after
        // the first. Unsent typing here stands.
        sleep(11)
        XCTAssertEqual(composer().value as? String, "started on the Mac and finished here")
    }
}
