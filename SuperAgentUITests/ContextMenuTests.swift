import XCTest

/// Holding a conversation in the projects tree.
///
/// The whole tree under a project used to be one list row, which meant one
/// shared context-menu interaction for every conversation in it: holding any
/// row lifted the entire block, and the menu could name a different
/// conversation than the one under your finger. The tree is one List row per
/// conversation now; these pin that each row answers for itself.
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

    private func dismissMenu() {
        // A tap on the dimmed backdrop, well away from the lifted row.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
    }

    func testHoldingAConversationTargetsThatConversation() {
        let second = app.staticTexts["Darken the footer"]
        XCTAssertTrue(second.waitForExistence(timeout: 10), "the harness project should list its second conversation")
        second.press(forDuration: 1.2)
        XCTAssertTrue(
            app.buttons["Delete \u{201C}Darken the footer\u{201D}"].waitForExistence(timeout: 5),
            "the menu should belong to the row under your finger"
        )
        dismissMenu()

        // …and the sibling row answers for itself, not for its neighbour.
        let first = app.staticTexts["Tighten the hero copy"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.press(forDuration: 1.2)
        XCTAssertTrue(
            app.buttons["Delete \u{201C}Tighten the hero copy\u{201D}"].waitForExistence(timeout: 5),
            "each conversation should carry its own menu"
        )
    }
}
