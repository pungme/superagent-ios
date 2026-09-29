import XCTest

/// How long a long conversation takes to be on screen. Not a pass/fail on a
/// number — the simulator is not a phone — but the figure is in the log
/// (OPEN_MS=…) so a change can be measured against the one before it.
final class OpenTimeTests: XCTestCase {
    func testALongConversationOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-longTranscript", "-openChat", "c1", "-tab", "projects"]
        let start = Date()
        app.launch()
        // The newest reply is at the bottom; the transcript opens on it.
        let last = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Round 400'")).firstMatch
        let lastVisible = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Have a look in the pane'")).firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 60) || lastVisible.waitForExistence(timeout: 60),
                      "the end of the conversation is on screen")
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("OPEN_MS=\(ms)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "long-open"
        shot.lifetime = .keepAlways
        add(shot)
        // Coming back to it — the second open, with everything cached.
        app.navigationBars.buttons.firstMatch.tap()
        let again = Date()
        app.staticTexts["Tighten the hero copy"].firstMatch.tap()
        XCTAssertTrue(lastVisible.waitForExistence(timeout: 60))
        print("REOPEN_MS=\(Int(Date().timeIntervalSince(again) * 1000))")
    }
}
