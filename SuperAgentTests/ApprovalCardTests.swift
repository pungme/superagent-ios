import XCTest
@testable import SuperAgent

/// Letting an agent use the Mac needs Face ID on the phone before its yes.
final class ApprovalCardTests: XCTestCase {
    func testOnlyUsingTheMacNeedsFaceIdFirst() {
        XCTAssertTrue(ApprovalCard.isMacOnly("mcp__cove-browser__computer_use"))
        for other in ["Bash", "Write", "mcp__cove-browser__mail_send", "mcp__cove-browser__computer_state", ""] {
            XCTAssertFalse(ApprovalCard.isMacOnly(other), other)
        }
    }
}
