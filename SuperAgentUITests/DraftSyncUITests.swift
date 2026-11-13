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

    /// Save for later, as on the Mac: the chip lists what was set aside, one
    /// goes back in the box, and the send button's menu sets the box aside.
    func testSavedPromptsComeBackAndTheBoxCanBeSetAside() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects", "-withSaved"]
        app.launch()
        func composer() -> XCUIElement {
            app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        }
        let chip = app.buttons["saved-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        XCTAssertEqual(chip.label, "2 saved for later")
        chip.tap()
        let first = app.buttons["Make the pricing cards yearly by default"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let put = app.buttons["Put in the message box"]
        XCTAssertTrue(put.waitForExistence(timeout: 5))
        put.tap()
        let deadline = Date().addingTimeInterval(5)
        while composer().value as? String != "Make the pricing cards yearly by default", Date() < deadline { usleep(200_000) }
        XCTAssertEqual(composer().value as? String, "Make the pricing cards yearly by default")
        XCTAssertEqual(app.buttons["saved-chip"].label, "1 saved for later")

        // Hold Send: "Save for later" sets it aside again and empties the box.
        app.buttons["Send"].press(forDuration: 0.8)
        let save = app.buttons["save-for-later"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let gone = NSPredicate { _, _ in app.buttons["saved-chip"].label == "2 saved for later" }
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 5)
        XCTAssertNotEqual(composer().value as? String, "Make the pricing cards yearly by default")
        XCUIScreen.main.screenshot().pngRepresentation.write(toFileSafely: "saved-chip")
    }

    /// The scroll-to-the-end button stays away while the transcript is at its
    /// end: it used to sit over the end of the last option and take the tap
    /// meant for it. An option is then answerable all along its width.
    func testTheLastOptionIsTappableAlongItsWholeWidth() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects", "-withAsk"]
        app.launch()
        let wait = app.buttons["Wait"]
        XCTAssertTrue(wait.waitForExistence(timeout: 15))
        sleep(2)
        XCTAssertFalse(app.buttons["scroll-to-latest"].exists, "nothing over the options while at the end")
        // Its right-hand end, where the arrow is.
        wait.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Sending"].waitForExistence(timeout: 5), "the answer went out as a message")
    }
}

private extension Data {
    func write(toFileSafely name: String) {
        let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] ?? NSTemporaryDirectory()
        try? write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
