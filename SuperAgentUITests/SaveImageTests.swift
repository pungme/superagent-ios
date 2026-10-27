import XCTest

/// A picture opened full screen can be kept: saved to Photos, or shared.
/// The harness puts a reply with a picture in it (`-imageReply`).
final class SaveImageTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-sidebar.collapsedGroups", "", "-openChat", "c1", "-imageReply"]
        app.launch()
    }

    func testAPictureOpenedFullScreenCanBeSavedAndShared() {
        // The picture in the reply, once it has loaded.
        let picture = app.images["The app on a phone"]
        XCTAssertTrue(picture.waitForExistence(timeout: 20), "the reply should show its picture")
        picture.tap()

        let save = app.buttons["Save to Photos"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the viewer should offer Save")
        XCTAssertTrue(app.buttons["Share"].exists, "and Share")

        // Photos asks once; say yes when it does.
        addUIInterruptionMonitor(withDescription: "Photos") { alert in
            for label in ["Allow", "Allow Access to All Photos", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        save.tap()
        // The first time Photos asks, say yes; once it has been allowed there is
        // no alert and the confirmation is up for under two seconds, so look for
        // it as often as for the alert rather than waiting for one first.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let toast = app.staticTexts["Saved to Photos"]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !toast.exists {
            for label in ["Allow", "OK"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
            }
            usleep(100_000)
        }
        XCTAssertTrue(toast.exists, "saving should say it worked")
    }

    /// Swiping the full-screen picture goes to the next one in the conversation,
    /// not only to the next in the same message.
    func testSwipingGoesToTheNextPictureInTheConversation() {
        app.terminate()
        app.launchArguments += ["-imageReply2"]
        app.launch()
        let picture = app.images["The app on a phone"]
        XCTAssertTrue(picture.waitForExistence(timeout: 20), "the first reply shows its picture")
        picture.tap()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 5), "the viewer says where it is")
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 of 2"].waitForExistence(timeout: 10), "a swipe goes to the next picture")
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 5), "and back")
    }
}
