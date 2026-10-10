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
        XCTAssertTrue(app.buttons["Pause the loop"].isHittable, "and a Pause")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "loop-bar"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAPausedLoopSaysSoAndOffersResume() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-withLoop", "-loopPaused", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Paused every 5m · run 3"].waitForExistence(timeout: 10),
                      "held, with no next round promised")
        XCTAssertTrue(app.buttons["Resume the loop"].isHittable)
        XCTAssertTrue(app.buttons["Stop the loop"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "loop-paused"
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

    /// A round the loop sent is shown as one: marked Loop, what was asked,
    /// and none of the instructions that went to the agent with it.
    func testALoopRoundIsShownWithoutItsInstructions() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-withLoop", "-openChat", "c1", "-tab", "projects"]
        app.launch()
        let round = app.descendants(matching: .any)["loop-round"].firstMatch
        XCTAssertTrue(round.waitForExistence(timeout: 15))
        XCTAssertTrue(round.label.contains("LOOP · EVERY 5M"), round.label)
        XCTAssertTrue(round.label.contains("Check the hero on a phone"), round.label)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'repeats on a timer'")).firstMatch.exists)
    }

    /// An option picked while the agent waits on its question goes bare; picked
    /// once the agent is at work on something else, it goes with the question,
    /// so it does not read as an answer to whatever came last.
    func testAnOptionCarriesItsQuestionOnlyWhenItIsAnsweredLate() {
        for late in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-sidebarHarness", "-withAsk", "-openChat", "c1", "-tab", "projects"]
                + (late ? ["-askLate"] : [])
            app.launch()
            let option = app.buttons["Ship it"].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 15), "late=\(late)")
            option.tap()
            // What went out waits for the Mac, which a harness has none of.
            XCTAssertTrue(app.staticTexts["Waiting for the Mac"].firstMatch.waitForExistence(timeout: 10)
                          || app.staticTexts["Sending"].firstMatch.waitForExistence(timeout: 2), "late=\(late)")
            let quoted = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Ship the hero tonight?'"))
            // The question is on screen once in its own card; a second time only as the quote.
            XCTAssertEqual(quoted.count, late ? 2 : 1, "late=\(late)")
            app.terminate()
        }
    }
}
