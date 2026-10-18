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
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK"] where springboard.buttons[label].waitForExistence(timeout: 3) {
            springboard.buttons[label].tap()
            break
        }
        app.tap() // lets the interruption monitor run if the alert came through it
        XCTAssertTrue(app.staticTexts["Saved to Photos"].waitForExistence(timeout: 10),
                      "saving should say it worked")
    }
}
