import XCTest
@testable import SuperAgent

final class ConductorChatTests: XCTestCase {
    private func decode(_ extra: String) throws -> WireChat {
        let json = "{\"id\":\"c1\",\"workspaceId\":\"w1\",\"updatedAt\":1,\"live\":false," + extra + "}"
        return try JSONDecoder().decode(WireChat.self, from: Data(json.utf8))
    }

    func testASessionLeadsWithItsNumber() throws {
        let c = try decode("\"title\":\"Fix the header\",\"conductor\":\"session\",\"ticket\":101")
        XCTAssertEqual(c.displayTitle, "#101 Fix the header")
        XCTAssertFalse(c.isClosedSession)
    }

    func testAClosedSessionIsHidden() throws {
        let c = try decode("\"title\":\"Old\",\"conductor\":\"session\",\"ticket\":102,\"closed\":true")
        XCTAssertTrue(c.isClosedSession)
    }

    func testMainAndOrdinaryChats() throws {
        let m = try decode("\"title\":null,\"conductor\":\"main\"")
        XCTAssertTrue(m.isConductorMain)
        XCTAssertEqual(m.displayTitle, "Conductor")
        let o = try decode("\"title\":\"Plain\"")
        XCTAssertEqual(o.displayTitle, "Plain")
        XCTAssertFalse(o.isConductorMain || o.isClosedSession)
    }
}
