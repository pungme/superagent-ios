import XCTest

/// A /loop running on the Mac shows on the phone too, with a way to stop it.
///
/// The loop used to live inside the Mac window's chat view, so the phone never
/// knew one was running — nothing on screen said the agent would come back
/// every five minutes, and nothing here could stop it.
final class LoopBarTests: XCTestCase {
    func testARunningLoopShowsWithStop() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-withLoop", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Looping every 5m · run 3 · next in'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), "the loop's bar says what it is doing")
        XCTAssertTrue(app.staticTexts["“Check the hero on a phone and tighten anything that wraps”"].exists, "and what it repeats")
        XCTAssertTrue(app.buttons["Stop the loop"].isHittable, "with a Stop within reach")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "loop-bar"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNoLoopNoBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Narrow, the headline holds'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Stop the loop"].exists, "no loop, no bar")
    }
}
