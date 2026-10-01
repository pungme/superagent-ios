import XCTest

/// The conversations that belong to no project are listed in the sidebar,
/// above Projects, the way the Mac lists them — not behind a "Chats" row.
final class SidebarChatsTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // On an iPad the sidebar remembers whether it was showing Activity or
        // Projects; another test's choice must not decide what this one sees.
        app.launchArguments = ["-sidebarHarness", "-tab", "projects", "-sidebar.mode", "projects"] + extra
        app.launch()
        // The fold is remembered between launches; start from open.
        let show = app.buttons["Show chats"]
        if show.waitForExistence(timeout: 3) { show.tap() }
        return app
    }

    func testLooseChatsAreListedAboveProjects() {
        let app = launch()
        let chat = app.staticTexts["Rename the screenshots on my desktop"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10), "the Computer's chat is in the sidebar itself")
        let projects = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Projects'")).firstMatch
        XCTAssertTrue(projects.exists)
        XCTAssertLessThan(chat.frame.minY, projects.frame.minY, "above Projects")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "sidebar-chats"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testFoldingPutsThemAwayAndSaysHowMany() {
        let app = launch()
        let chat = app.staticTexts["Rename the screenshots on my desktop"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        app.buttons["Hide chats"].tap()
        XCTAssertTrue(app.buttons["Show chats"].waitForExistence(timeout: 5))
        XCTAssertFalse(chat.exists, "folded away")
        app.buttons["Show chats"].tap()
        XCTAssertTrue(chat.waitForExistence(timeout: 5), "and back")
    }

    func testMoreThanSixOffersTheWholeList() {
        let app = launch(["-manyChats"])
        XCTAssertTrue(app.staticTexts["Loose chat 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Loose chat 8"].exists, "only the newest six are listed")
        let all = app.buttons["Show all 9"]
        // Below the fold on a phone: the list only realises what is on screen.
        if !all.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        XCTAssertTrue(app.staticTexts["Loose chat 8"].waitForExistence(timeout: 5), "the full list has the rest")
    }
}
