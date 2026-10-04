import XCTest

/// A conversation pins from inside it, not only by holding its row.
final class PinFromChatTests: XCTestCase {
    func testThePinButtonPinsAndUnpins() {
        let app = XCUIApplication()
        app.launchArguments = ["-sidebarHarness", "-openChat", "c1", "-tab", "projects"]
        app.launch()

        let pin = app.buttons["pin-chat"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "the conversation offers Pin")
        let before = pin.label
        pin.tap()
        var flipped = false
        for _ in 0..<20 where !flipped {
            flipped = pin.label != before
            if !flipped { usleep(250_000) }
        }
        XCTAssertTrue(flipped, "tapping it flips Pin and Unpin: \(before) → \(pin.label)")
        pin.tap()
        var back = false
        for _ in 0..<20 where !back {
            back = pin.label == before
            if !back { usleep(250_000) }
        }
        XCTAssertTrue(back, "and back again")
    }
}
