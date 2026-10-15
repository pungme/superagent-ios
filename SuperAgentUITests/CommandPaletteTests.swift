import XCTest

/// ⌘K's palette: what it lists, and that choosing a row goes there.
///
/// Opened with `-palette` rather than by pressing ⌘K: the shortcut is a
/// SwiftUI keyboardShortcut, which the system delivers, and the question here
/// is what the palette does once it is open. Runs against the harness, so the
/// contents are fixed and no Mac is involved.
final class CommandPaletteTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-sidebar.collapsedGroups", "", "-palette"]
        app.launch()
    }

    func testItOpensOnTheRecentConversationsAndActions() {
        XCTAssertTrue(app.textFields["palette-field"].waitForExistence(timeout: 10),
                      "the palette should open with its field")
        let rows = app.descendants(matching: .any).matching(identifier: "palette-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(rows.count, 3, "recent conversations and actions")
        XCTAssertTrue(rows.containing(.staticText, identifier: "Settings").firstMatch.exists,
                      "Settings is one of the actions")
    }

    func testChoosingAConversationOpensIt() {
        XCTAssertTrue(app.textFields["palette-field"].waitForExistence(timeout: 10))
        let row = app.descendants(matching: .any).matching(identifier: "palette-row")
            .containing(.staticText, identifier: "Fix the flaky auth test").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertFalse(app.textFields["palette-field"].waitForExistence(timeout: 2),
                       "the palette should close")
        XCTAssertTrue(app.staticTexts["Message Codex about mobile-app"].waitForExistence(timeout: 5)
                      || app.navigationBars.staticTexts["Fix the flaky auth test"].waitForExistence(timeout: 5),
                      "the conversation should be on screen")
    }
}
