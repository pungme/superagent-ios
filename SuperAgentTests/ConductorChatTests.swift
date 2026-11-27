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

final class ConductorStateDecodeTests: XCTestCase {
    func testTheMacsSessionListDecodes() throws {
        let json = """
        {"chatId":"m","routing":"auto","unlinked":[],"sessions":[
          {"chatId":"a","title":"Fix header","ticket":101,"summary":"","status":"needs-you","updatedAt":1,
           "approval":{"requestId":"r","preview":"Run: make"},"branch":"fix-header","unmerged":2,"files":["a.ts","b.ts"]},
          {"chatId":"b","title":"Pricing","ticket":102,"summary":"Done.","status":"idle","updatedAt":2}]}
        """
        let s = try JSONDecoder().decode(WireConductorState.self, from: Data(json.utf8))
        XCTAssertEqual(s.routing, "auto")
        XCTAssertEqual(s.sessions.count, 2)
        XCTAssertEqual(s.sessions[0].approval?.preview, "Run: make")
        XCTAssertEqual(s.sessions[0].files?.count, 2)
        XCTAssertNil(s.sessions[1].branch)
    }
}
