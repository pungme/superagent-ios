import XCTest
@testable import SuperAgent

/// Letting an agent use the Mac is agreed to at the Mac. The phone shows the
/// request and can refuse it, but offers no Approve for it.
final class ApprovalCardTests: XCTestCase {
    func testOnlyUsingTheMacIsTheMacsToAllow() {
        XCTAssertTrue(ApprovalCard.isMacOnly("mcp__cove-browser__computer_use"))
        for other in ["Bash", "Write", "mcp__cove-browser__mail_send", "mcp__cove-browser__computer_state", ""] {
            XCTAssertFalse(ApprovalCard.isMacOnly(other), other)
        }
    }
}
