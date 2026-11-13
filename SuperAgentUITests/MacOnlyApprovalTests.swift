import XCTest

/// A request to let the agent use the Mac is shown on the phone, can be
/// refused from it, and allowed from it too, after Face ID.
final class MacOnlyApprovalTests: XCTestCase {
    private func open(_ flag: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects", flag]
        app.launch()
        return app
    }

    func testUsingTheMacCanBeAllowedOrDeniedFromThePhone() {
        let app = open("-macApproval")
        let note = app.staticTexts["approval-mac-only"]
        for _ in 0..<5 where !note.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(note.exists, "the card says what the yes takes")
        XCTAssertEqual(note.label, "Face ID first. ⌥Esc on your Mac stops it at any time.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'wants to use your Mac'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Deny"].exists, "a no can be given from here")
        XCTAssertTrue(app.buttons["Approve"].exists, "and a yes")
    }

    func testAnOrdinaryRequestStillHasBothAnswers() {
        let app = open("-toolApproval")
        let approve = app.buttons["Approve"]
        for _ in 0..<5 where !approve.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(approve.exists)
        XCTAssertTrue(app.buttons["Deny"].exists)
        XCTAssertFalse(app.staticTexts["approval-mac-only"].exists)
    }
}
