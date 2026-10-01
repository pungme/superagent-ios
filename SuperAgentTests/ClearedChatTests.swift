import Testing
import Foundation
@testable import SuperAgent

/// Clearing a conversation on the Mac starts its numbering again at 1. A phone
/// still holding the old events read every new one as a repeat and dropped it:
/// the old conversation stayed on screen and whatever was sent vanished.
@MainActor
struct ClearedChatTests {
    private func connection() -> Connection {
        Connection(machine: PairedMachine(id: "cleared-\(UUID().uuidString)", name: "Mac", relay: "wss://example.invalid",
                                          deviceId: "d", secret: Data(repeating: 1, count: 32),
                                          token: "t", pairedAt: .now))
    }
    private func ev(_ seq: Int, ts: Double? = nil, _ data: WireEventData) -> WireEvent {
        WireEvent(chatId: "c", seq: seq, ts: ts ?? Double(seq) * 1000, data: data)
    }
    /// A phone that has read fifty events of a conversation.
    private func caughtUp() async throws -> Connection {
        let c = connection()
        c.subscribe(chatId: "c")
        for i in 1...50 { c._applyForTests(.event(ev(i, .assistant(id: "a\(i)", text: "old \(i)")))) }
        try await Task.sleep(for: .milliseconds(80))
        #expect(c.transcripts["c"]?.lastSeq == 50)
        return c
    }
    private let later = 9_000_000.0

    @Test func theMacSayingResetEmptiesTheChat() async throws {
        let c = try await caughtUp()
        c._applyForTests(.reset(chatId: "c"))
        #expect(c.transcripts["c"]?.events.isEmpty == true)
        #expect(c.transcripts["c"]?.lastSeq == 0)
        // The new conversation then arrives from 1 and is kept.
        c._applyForTests(.event(ev(1, ts: later, .user(id: "u1", text: "fresh start", images: [], from: .desktop, replyTo: nil))))
        try await Task.sleep(for: .milliseconds(80))
        #expect(c.transcripts["c"]?.events.count == 1)
    }

    @Test func eventsHeldFromBeforeAResetAreNotAppliedAfterIt() async throws {
        let c = try await caughtUp()
        c._applyForTests(.event(ev(51, .assistant(id: "a51", text: "old 51"))))
        c._applyForTests(.reset(chatId: "c"))
        try await Task.sleep(for: .milliseconds(80))
        #expect(c.transcripts["c"]?.events.isEmpty == true)
    }

    /// A Mac from before `reset` existed just starts sending low numbers.
    @Test func aRestartedLogIsNoticedWithoutBeingTold() async throws {
        let c = try await caughtUp()
        c._applyForTests(.event(ev(1, ts: later, .user(id: "u1", text: "after the clear", images: [], from: .desktop, replyTo: nil))))
        c._applyForTests(.event(ev(2, ts: later + 1, .assistant(id: "n2", text: "new reply"))))
        try await Task.sleep(for: .milliseconds(80))
        let t = try #require(c.transcripts["c"])
        #expect(t.lastSeq == 2)
        #expect(t.events.map(\.seq) == [1, 2])
        if case let .assistant(_, text) = t.events[1].data { #expect(text == "new reply") } else { Issue.record("not the new reply") }
    }

    /// The case that was reported: a message sent from the phone into a
    /// cleared chat went from the outbox to nowhere.
    @Test func aMessageSentIntoAClearedChatStays() async throws {
        let c = try await caughtUp()
        c.sendMessage(chatId: "c", text: "Why do I get every email")
        let id = try #require(c.transcripts["c"]?.outbox.first?.id)
        c._applyForTests(.event(ev(1, ts: later, .user(id: id, text: "Why do I get every email", images: [], from: .ios, replyTo: nil))))
        try await Task.sleep(for: .milliseconds(80))
        let t = try #require(c.transcripts["c"])
        #expect(t.outbox.isEmpty)
        #expect(t.events.count == 1)
        if case let .user(echoed, _, _, _, _) = t.events[0].data { #expect(echoed == id) } else { Issue.record("no user message") }
    }

    /// The Mac resending something already held is still just a repeat — even
    /// when its time is a moment off, as a live event's is from its stored copy.
    @Test func aRealRepeatChangesNothing() async throws {
        let c = try await caughtUp()
        c._applyForTests(.event(ev(50, ts: 50_001, .assistant(id: "a50", text: "old 50"))))
        c._applyForTests(.event(ev(49, .assistant(id: "a49", text: "old 49"))))
        try await Task.sleep(for: .milliseconds(80))
        #expect(c.transcripts["c"]?.events.count == 50)
        #expect(c.transcripts["c"]?.lastSeq == 50)
    }

    @Test func catchingUpSaysWhenItsLastEventWas() throws {
        let frame = ClientFrame.subscribe(chatId: "c1", afterSeq: 7, afterTs: 1234)
        let sub = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any]
        #expect(sub?["afterSeq"] as? Int == 7)
        #expect(sub?["afterTs"] as? Double == 1234)
        // Nothing held: nothing to say, and the key is left out.
        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.subscribe(chatId: "c1", afterSeq: 0))) as? [String: Any]
        #expect(fresh?["afterTs"] == nil)
        let reset = try JSONDecoder().decode(ServerFrame.self, from: Data(#"{"t":"reset","chatId":"c1"}"#.utf8))
        if case let .reset(chatId) = reset { #expect(chatId == "c1") } else { Issue.record("reset did not decode") }
    }
}

/// A phone holding nothing of a chat asks for its tail, and starts wherever
/// the Mac starts it.
@MainActor
struct TailTests {
    private func ev(_ seq: Int) -> WireEvent {
        WireEvent(chatId: "c", seq: seq, ts: Double(seq) * 1000, data: .assistant(id: "a\(seq)", text: "\(seq)"))
    }

    @Test func aFreshCopyStartsWhereTheTailDoes() {
        var t = Transcript()
        t.startsAnywhere = true
        let r1 = t.apply(ev(5748))
        #expect(r1)
        let r2 = t.apply(ev(5749))
        #expect(r2)
        #expect(t.lastSeq == 5749)
        #expect(t.events.count == 2)
        // After the first event a jump is a gap again, not a new start.
        let r3 = t.apply(ev(5800))
        #expect(!r3)
        #expect(t.lastSeq == 5749)
    }

    @Test func withoutAskingForATailTheStartIsStillOne() {
        var t = Transcript()
        let r4 = t.apply(ev(25))
        #expect(!r4)
        #expect(t.events.isEmpty)
        let r5 = t.apply(ev(1))
        #expect(r5)
    }

    @Test func theSubscribeFrameCarriesTheTail() throws {
        let frame = ClientFrame.subscribe(chatId: "c1", afterSeq: 0, tail: 400)
        let sub = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any]
        #expect(sub?["tail"] as? Int == 400)
        let caughtUp = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.subscribe(chatId: "c1", afterSeq: 9))) as? [String: Any]
        #expect(caughtUp?["tail"] == nil)
    }
}
