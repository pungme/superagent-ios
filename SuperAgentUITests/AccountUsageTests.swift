import XCTest

/// The phone says which account a chat spends and how full each one is, and a
/// chat can be moved to another — the Mac's Account pill and usage, here too.
final class AccountUsageTests: XCTestCase {
    func testTheAccountPillShowsUsageAndSwitches() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let pill = app.buttons["account-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "a chat with several accounts shows the Account pill")
        XCTAssertTrue(pill.label.contains("Claude"), "named for the account it is on: \(pill.label)")
        XCTAssertTrue(pill.label.contains("99%"), "with its fullest window: \(pill.label)")
        pill.tap()
        let other = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'campaigns@'")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "the menu lists the other accounts")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '5-hour 41%'")).firstMatch.exists,
            "each with its usage")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "account-menu"
        shot.lifetime = .keepAlways
        add(shot)
        other.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        // The pill follows the pick.
        var moved = false
        for _ in 0..<20 where !moved {
            moved = pill.label.contains("campaigns@")
            if !moved { usleep(250_000) }
        }
        XCTAssertTrue(moved, "the pill names the account the chat moved to: \(pill.label)")
    }
}
