import XCTest

/// A file opened on the phone can be kept: Save fetches the whole file from
/// the Mac and opens the share sheet, which has Save to Files.
final class SaveFileTests: XCTestCase {
    func testAnOpenFileCanBeSaved() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let files = app.buttons["Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 10), "the conversation's Files button")
        files.tap()
        let row = app.staticTexts["notes.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the harness file is listed")
        row.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'headline holds'")).firstMatch
            .waitForExistence(timeout: 10), "the file opens")

        let save = app.buttons["save-file"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the viewer offers Save")
        save.tap()
        let saveToFiles = app.buttons["Save to Files"].firstMatch
        let sheet = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10) || sheet.exists,
                      "the share sheet opens, with Save to Files")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "save-file-sheet"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
