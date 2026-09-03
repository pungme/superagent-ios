import Foundation
import Testing
@testable import SuperAgent

/// Decodes the fixtures the desktop repo owns. A shape change on either side lands here.
struct ProtocolTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Marker.self).url(forResource: name, withExtension: "json"),
                               "fixture \(name).json missing — is the desktop repo checked out beside this one?")
        return try Data(contentsOf: url)
    }
    private final class Marker {}

    struct Frames: Decodable {
        var server: [ServerFrame]
        var events: [WireEvent]
    }

    @Test func decodesEveryServerFrame() throws {
        let f = try JSONDecoder().decode(Frames.self, from: fixture("frames"))
        #expect(f.server.count == 10)
        guard case let .welcome(machine, tree, chats) = f.server[0] else { Issue.record("welcome"); return }
        #expect(machine.name == "Fixture Mac")
        #expect(machine.protocolVersion == 1)
        #expect(tree.first?.workspaces.first?.status == .working)
        #expect(chats.first?.live == true)
        guard case let .paired(token, _) = f.server[1] else { Issue.record("paired"); return }
        #expect(token == "tok_abc")
        guard case .bye(let reason) = f.server[2] else { Issue.record("bye"); return }
        #expect(reason == "unauthorized")
        guard case let .delta(chatId, text) = f.server[3] else { Issue.record("delta"); return }
        #expect(chatId == "c1" && text == "On ")
        guard case let .status(_, status) = f.server[4] else { Issue.record("status"); return }
        #expect(status == .needsYou)
        guard case let .res(id1, r1) = f.server[6], case .success(let data) = r1 else { Issue.record("res ok"); return }
        #expect(id1 == "r1")
        struct R: Decodable { var chatId: String }
        #expect(try JSONDecoder().decode(R.self, from: data).chatId == "c9")
        guard case let .res(_, r2) = f.server[7], case .failure(let err) = r2 else { Issue.record("res err"); return }
        #expect(err.code == "gone")
        guard case .pong = f.server[8] else { Issue.record("pong"); return }
        guard case let .openFile(ws, path, chatId) = f.server[9] else { Issue.record("openFile"); return }
        #expect(ws == "w1" && path == "docs/spec.pdf" && chatId == "c1")
    }

    @Test func decodesEveryEventKindAndKeepsUnknownOnes() throws {
        let f = try JSONDecoder().decode(Frames.self, from: fixture("frames"))
        let kinds = f.events.map(\.data.kind)
        #expect(kinds == ["session", "user", "thinking", "tool", "tool_result", "diff", "approval",
                          "approval_end", "assistant", "notice", "turn_end", "something_new"])
        guard case let .user(id, text, images, from, _) = f.events[1].data else { Issue.record("user"); return }
        #expect(id == "L-1" && text == "ship it" && from == .ios && images.first?.size == 12345)
        guard case let .diff(_, file, hunks) = f.events[5].data else { Issue.record("diff"); return }
        #expect(file == "app.ts" && hunks == [DiffHunk(removed: ["y"], added: ["z"])])
        guard case let .approvalEnd(_, outcome, by) = f.events[7].data else { Issue.record("approval_end"); return }
        #expect(outcome == .approved && by == .ios)
        guard case let .turnEnd(ok, _, cost, tokens) = f.events[10].data else { Issue.record("turn_end"); return }
        #expect(ok && cost == 0.12 && tokens == 15)
        guard case .unknown(let k) = f.events[11].data else { Issue.record("unknown"); return }
        #expect(k == "something_new")
    }

    @Test func transcriptAppliesInOrderAndFlagsGaps() throws {
        let f = try JSONDecoder().decode(Frames.self, from: fixture("frames"))
        var t = Transcript()
        for e in f.events.prefix(3) {
            let ok = t.apply(e)
            #expect(ok)
        }
        #expect(t.lastSeq == 3)
        let replay = t.apply(f.events[1])   // replay of an old one is harmless
        #expect(replay == true)
        let gap = t.apply(f.events[5])      // seq 6 after 3 is a gap
        #expect(gap == false)
        #expect(t.lastSeq == 3)
    }

    @Test func clientFramesEncodeTheWireShape() throws {
        let hello = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.hello(device: "d", token: "t", app: "ios/1"))) as? [String: Any]
        #expect(hello?["t"] as? String == "hello")
        #expect(hello?["v"] as? Int == protocolVersion)
        let sub = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.subscribe(chatId: "c1", afterSeq: 7))) as? [String: Any]
        #expect(sub?["afterSeq"] as? Int == 7)
        let req = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.req(id: "r", method: "chat.send", params: .object(["chatId": .string("c1")])))) as? [String: Any]
        #expect((req?["params"] as? [String: Any])?["chatId"] as? String == "c1")
    }

    @Test func parsesPairingLinks() throws {
        let payload = PairPayload(v: 1, name: "Mac", relay: "wss://relay.example", m: String(repeating: "ab", count: 32), k: Data(repeating: 7, count: 32).base64URL)
        let json = try JSONEncoder().encode(payload)
        let link = "superagent://pair#" + json.base64URL
        let parsed = try #require(PairPayload.parse(link))
        #expect(parsed == payload)
        #expect(parsed.secret?.count == 32)
        #expect(PairPayload.parse("https://example.com") == nil)
    }
}
