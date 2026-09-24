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
            "-sidebar.collapsedGroups", "",
            "-sidebar.reposOpen", ""
        ]
        app.launch()
    }

    private func dismissMenu() {
        // A tap on the dimmed backdrop, well away from the lifted row.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
    }

    /// A List only builds the rows on screen: scroll until this one exists.
    private func find(_ text: String) -> XCUIElement {
        let el = app.staticTexts[text]
        for _ in 0..<6 where !el.waitForExistence(timeout: 1.5) { app.swipeUp() }
        return el
    }

    func testHoldingAConversationTargetsThatConversation() {
        let second = find("Darken the footer")
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

    /// Pins keep the order you set, and the hold menu moves them. The harness
    /// pins "Read the pricing page…" above "Why is the staging deploy slow?"
    /// even though the second had newer activity: the pin order wins.
    func testPinnedRowsMoveWithTheHoldMenu() {
        let pricing = app.staticTexts["Read the pricing page back to me"]
        let staging = app.staticTexts["Why is the staging deploy slow?"]
        XCTAssertTrue(pricing.waitForExistence(timeout: 10))
        XCTAssertTrue(staging.waitForExistence(timeout: 5))
        XCTAssertLessThan(pricing.frame.minY, staging.frame.minY, "pin order, not last activity")

        // The top pin can only go down.
        pricing.press(forDuration: 1.2)
        XCTAssertFalse(app.buttons["Move up"].waitForExistence(timeout: 2))
        let down = app.buttons["Move down"]
        XCTAssertTrue(down.waitForExistence(timeout: 5), "a pinned row offers Move down")
        down.tap()

        // The harness has no Mac to save to, but the order shows at once.
        let moved = app.staticTexts["Read the pricing page back to me"]
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(moved.frame.minY, app.staticTexts["Why is the staging deploy slow?"].frame.minY)
    }
}
