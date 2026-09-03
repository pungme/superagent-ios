import XCTest

/// Holding a conversation in the projects tree.
///
/// The whole tree under a project — repos, conversations, routines — is one
/// list row, so the system's context-menu lift raised the entire block: you
/// held "Darken the footer" and watched eleven rows float up, with the menu's
/// own wording as the only clue to which one you were about to delete. The fix
/// is an explicit preview of just the held row; this pins it.
final class ContextMenuTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The projects view, with every group open — the stored mode and
        // collapse state of whoever ran the app last must not steer a test.
        app.launchArguments = [
            "-sidebarHarness",
            "-sidebar.mode", "projects",
            "-sidebar.collapsedGroups", ""
        ]
        app.launch()
    }

    func testHoldingAConversationLiftsOnlyThatRow() {
        let row = app.staticTexts["Darken the footer"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the harness project should list its second conversation")
        row.press(forDuration: 1.2)

        // The action names the conversation…
        let delete = app.buttons["Delete \u{201C}Darken the footer\u{201D}"]
        if !delete.waitForExistence(timeout: 5) {
            print("=== BUTTONS ON SCREEN ===")
            for i in 0..<min(app.buttons.count, 40) { print("btn:", app.buttons.element(boundBy: i).label) }
            print("=== MENU ITEMS ===")
            for i in 0..<min(app.menuItems.count, 20) { print("menu:", app.menuItems.element(boundBy: i).label) }
            print("=== OTHER tree-row-preview exists:", app.descendants(matching: .any)["tree-row-preview"].exists)
        }
        XCTAssertTrue(delete.exists, "the menu should offer to delete the held conversation")

        // …and the lifted preview is the one row, not the tree around it.
        let preview = app.descendants(matching: .any)["tree-row-preview"]
        XCTAssertTrue(preview.exists, "the lift should be the explicit row preview, not the whole list row")
        XCTAssertEqual(preview.label, "Darken the footer")
    }
}
