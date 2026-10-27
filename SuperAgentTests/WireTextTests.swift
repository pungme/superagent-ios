import XCTest
@testable import SuperAgent

final class WireTextTests: XCTestCase {
    func testAHugeMessageIsClippedAndSaysSo() {
        let big = String(repeating: "x", count: 1_000_000)
        let out = WireText.clip(big)
        XCTAssertLessThan(out.utf8.count, 21_000)
        XCTAssertTrue(out.contains("more characters, not shown on the phone"))
        XCTAssertTrue(out.hasPrefix(String(repeating: "x", count: 20_000)))
    }

    func testAnOrdinaryMessageIsUntouched() {
        let text = String(repeating: "word ", count: 3_000)
        XCTAssertEqual(WireText.clip(text), text)
        XCTAssertEqual(WireText.clip(""), "")
    }
}
