import XCTest

/// A request to let the agent use the Mac is shown on the phone, can be
/// refused from it, and offers no Approve: that yes is given at the Mac.
final class MacOnlyApprovalTests: XCTestCase {
    private func open(_ flag: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects", flag]
        app.launch()
        return app
    }

    func testUsingTheMacIsOnlyDeniedFromThePhone() {
        let app = open("-macApproval")
        let note = app.staticTexts["approval-mac-only"]
        for _ in 0..<5 where !note.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(note.exists, "the card says where to allow it")
        XCTAssertEqual(note.label, "Allow this on your Mac.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'wants to use your Mac'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Deny"].exists, "a no can be given from here")
        XCTAssertFalse(app.buttons["Approve"].exists, "there is no yes to press")
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
