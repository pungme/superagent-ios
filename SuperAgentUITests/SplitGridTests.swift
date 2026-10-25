import XCTest

/// A Mac split on the phone is a grid, not windows side by side: the row under
/// Splits opens it, a tap on a card opens that conversation alone.
final class SplitGridTests: XCTestCase {
    func testASplitOpensAsAGridAndACardOpensOneChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-withSplit", "-tab", "projects"]
        app.launch()

        let row = app.buttons["split-row-s1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the Mac's split is listed under Splits")
        row.tap()
        let card = app.buttons["split-card-c1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "its conversations are a grid of cards")
        XCTAssertTrue(app.buttons["split-card-c2"].exists)
        card.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5) || app.textFields.firstMatch.waitForExistence(timeout: 5),
                      "a tap opens that conversation alone, with its composer")
        XCTAssertFalse(app.buttons["split-card-c2"].exists, "no grid beside it")
    }
}
