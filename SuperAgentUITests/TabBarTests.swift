import XCTest

/// The bottom bar, on a phone: Projects, Activity, Chat, Search, Settings.
/// Each tab is its own stack; these check every tab lands on its screen.
final class TabBarTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-sidebar.collapsedGroups", ""]
        app.launch()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Tap a tab and make sure the selection actually landed there. The glass
    /// bar animates between selections, and a tap aimed while it is still
    /// moving can land a slot over — that is a stale frame, not a real miss.
    private func select(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the bar should have a \(name) tab")
        for _ in 0..<4 where !button.isSelected {
            button.tap()
            usleep(400_000)
        }
        XCTAssertTrue(button.isSelected, "\(name) should be the selected tab")
    }

    func testEveryTabLandsOnItsScreen() throws {
        try XCTSkipIf(isPad, "the iPad keeps the Mac's split layout; there is no bar")

        // Projects is the default: the sidebar's rows are already here.
        XCTAssertTrue(app.staticTexts["landing-page"].waitForExistence(timeout: 10))

        select("Activity")
        XCTAssertTrue(app.staticTexts["Fix the flaky auth test"].waitForExistence(timeout: 5),
                      "Activity is the flat feed of every conversation")

        // Chat is the Computer's conversation list; a session is chosen from
        // here rather than the tab unexpectedly opening the newest one.
        select("Chat")
        XCTAssertTrue(app.staticTexts["Chats"].firstMatch.waitForExistence(timeout: 5))
        let chatRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Rename the screenshots")
        ).firstMatch
        XCTAssertTrue(chatRow.waitForExistence(timeout: 5),
                      "Chat should show the Computer conversation list")

        chatRow.tap()
        XCTAssertFalse(app.tabBars.firstMatch.waitForExistence(timeout: 1),
                       "a session should use the whole phone without the bottom bar")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5),
                      "Back to the chat list should restore the bottom bar")

        select("Settings")
        XCTAssertTrue(app.staticTexts["Paired Macs"].waitForExistence(timeout: 5))

        // And back: the Projects stack is where it was left.
        select("Projects")
        XCTAssertTrue(app.staticTexts["landing-page"].waitForExistence(timeout: 5))

        // Search goes last: selecting it morphs the whole bar into the search
        // field, and the other tabs are not reachable until it is dismissed.
        // Its circle floats outside the tab bar, so it is a plain button here.
        let search = app.buttons["Search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the trailing search circle should exist")
        search.tap()
        XCTAssertTrue(app.staticTexts["Search every conversation"].waitForExistence(timeout: 5))
    }
}
