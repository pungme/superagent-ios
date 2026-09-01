import XCTest

/// What a finger does to the two-column layout.
///
/// These exist because the bugs they cover cannot be reasoned about: tapping a
/// project pushed a second copy of the conversation on top of the first, gave
/// it a Back button that led to an empty pane, and left the sidebar unable to
/// say which conversation you were in. Every one of those is a question about
/// what happens when the app is touched, and nothing outside the process can
/// touch it reliably — a simulator's HID injection is not dependable from a
/// shell. XCUITest is in the process, so it is.
///
/// The app is launched against its own harness (`-sidebarHarness`), so the
/// contents are fixed and no Mac is involved.
final class SplitLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness"]
        app.launch()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func project(_ name: String) -> XCUIElement {
        app.buttons.containing(.staticText, identifier: name).firstMatch
    }

    func testTappingAProjectOpensItsConversation() {
        let row = project("landing-page")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar should list the harness projects")
        row.tap()
        XCTAssertTrue(
            app.staticTexts["Tighten the hero copy"].waitForExistence(timeout: 5),
            "tapping a project should show its conversation"
        )
    }

    /// The sidebar stays put on an iPad. That is the whole difference between a
    /// second column and a pushed screen, and it is what the first version got
    /// wrong.
    func testTheSidebarStaysWhileAConversationIsOpen() throws {
        try XCTSkipUnless(isPad, "one column has no sidebar to keep")
        project("landing-page").tap()
        XCTAssertTrue(app.staticTexts["Tighten the hero copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(project("mobile-app").exists, "the other projects should still be reachable")
    }

    /// Tapping the same project twice used to stack a second copy of the
    /// conversation, which is how a Back button appeared in a layout that has
    /// nothing to go back to.
    func testTappingTwiceDoesNotStackAndLeavesNoBackButton() throws {
        try XCTSkipUnless(isPad, "one column is a stack; Back belongs there")
        let row = project("landing-page")
        row.tap()
        XCTAssertTrue(app.staticTexts["Tighten the hero copy"].waitForExistence(timeout: 5))
        row.tap()
        row.tap()
        XCTAssertFalse(
            app.navigationBars.buttons["Back"].exists,
            "a conversation in the second column is the root; there is nothing behind it"
        )
        XCTAssertTrue(app.staticTexts["Tighten the hero copy"].exists, "and it is still the one on screen")
    }

    /// Opening a second conversation replaces the first rather than piling on.
    func testASecondConversationReplacesTheFirst() throws {
        try XCTSkipUnless(isPad, "one column pushes, and that is correct there")
        project("landing-page").tap()
        XCTAssertTrue(app.staticTexts["Tighten the hero copy"].waitForExistence(timeout: 5))
        project("mobile-app").tap()
        XCTAssertTrue(
            app.staticTexts["Fix the flaky auth test"].waitForExistence(timeout: 5),
            "the second column should now be the other conversation"
        )
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)
    }

    /// Activity is the other way of reading the same Mac: one flat list.
    func testActivityModeListsEveryConversation() {
        app.buttons["Activity"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Tighten the hero copy"].waitForExistence(timeout: 5),
            "Activity should list conversations from every project"
        )
        XCTAssertTrue(app.staticTexts["Fix the flaky auth test"].exists)
        XCTAssertTrue(app.staticTexts["Rename the screenshots on my desktop"].exists)
    }

    /// The bug that started this: opening a project must never wait on the Mac,
    /// and must never leave the sidebar unable to answer the next tap.
    func testTheSidebarKeepsAnsweringAfterOpeningAProject() {
        project("landing-page").tap()
        XCTAssertTrue(app.staticTexts["Tighten the hero copy"].waitForExistence(timeout: 5))
        // One column pushed the conversation over the sidebar, so come back to
        // it first. Two columns never left it.
        if !isPad {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 3), "a pushed conversation has a way back")
            back.tap()
        }
        let other = project("api")
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        XCTAssertTrue(
            app.staticTexts["Why is the staging deploy slow?"].waitForExistence(timeout: 5),
            "a second tap should be answered, not swallowed by a lock"
        )
    }
}
