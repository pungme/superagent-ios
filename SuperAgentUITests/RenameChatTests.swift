import XCTest

/// A conversation is renamed from inside it, by tapping its title, and from
/// its row in the sidebar by holding it.
final class RenameChatTests: XCTestCase {
    func testTappingTheTitleRenamesTheConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let title = app.buttons["chat-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the conversation shows its title")
        title.tap()
        let alert = app.alerts["Rename conversation"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "tapping the title asks for a new one")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        // Wherever the cursor lands in the old name, the new one has this in it.
        let before = title.label
        field.tap()
        field.typeText("Zed")
        alert.buttons["Save"].tap()

        var renamed = false
        for _ in 0..<20 where !renamed {
            renamed = title.label != before && title.label.contains("Zed")
            if !renamed { usleep(250_000) }
        }
        XCTAssertTrue(renamed, "the header shows the new name: \(before) → \(title.label)")
    }

    func testHoldingARowOffersRename() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-tab", "projects"]
        app.launch()
        // Any conversation row: the harness lists several under Chats.
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'screenshots'")).firstMatch
        for _ in 0..<6 where !row.waitForExistence(timeout: 1.5) { app.swipeUp() }
        XCTAssertTrue(row.exists, "a conversation is listed")
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5), "holding a conversation offers Rename")
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.alerts["Rename conversation"].waitForExistence(timeout: 5))
        app.alerts["Rename conversation"].buttons["Cancel"].tap()
    }
}
