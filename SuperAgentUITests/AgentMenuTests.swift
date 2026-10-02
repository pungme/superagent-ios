import XCTest

/// The agent pill offers every agent the Mac runs. Antigravity (Google's,
/// Gemini) was missing: a conversation the Mac had put on it said so, but
/// there was no way to pick it from the phone.
final class AgentMenuTests: XCTestCase {
    func testAllThreeAgentsAreOffered() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let pill = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Claude Code'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the agent pill is there")
        pill.tap()
        XCTAssertTrue(app.buttons["✓ Claude Code"].waitForExistence(timeout: 5), "the one in use is ticked")
        XCTAssertTrue(app.buttons["Codex"].exists)
        XCTAssertTrue(app.buttons["Antigravity"].exists, "Antigravity can be picked from the phone")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "agent-menu"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
