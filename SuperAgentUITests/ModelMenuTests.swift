import XCTest

/// The model menu shows the current line-up; the older versions the Mac's CLI
/// still offers sit under "Older models" instead of stretching the menu.
final class ModelMenuTests: XCTestCase {
    func testOlderVersionsAreFoldedAway() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let pill = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Model'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the model pill is there")
        pill.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Opus 5.5'")).firstMatch.waitForExistence(timeout: 5),
                      "the current Opus is in view")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Opus 4.6'")).firstMatch.exists,
                       "an older version is not")
        let older = app.buttons["Older models"]
        XCTAssertTrue(older.waitForExistence(timeout: 5), "they sit behind Older models")
        older.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Opus 4.6'")).firstMatch.waitForExistence(timeout: 5),
                      "which opens them")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "model-menu-older"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
