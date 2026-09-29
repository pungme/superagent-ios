import Testing
import Foundation
@testable import SuperAgent

/// A catch-up arrives as one frame per event; they are applied together a
/// tick later, and a delta arriving meanwhile keeps its place after them.
@MainActor
struct EventBatchTests {
    private func connection() -> Connection {
        Connection(machine: PairedMachine(id: "m", name: "Mac", relay: "wss://example.invalid",
                                          deviceId: "d", secret: Data(repeating: 1, count: 32),
                                          token: "t", pairedAt: .now))
    }
    private func ev(_ seq: Int, _ data: WireEventData) -> WireEvent {
        WireEvent(chatId: "c", seq: seq, ts: Double(seq), data: data)
    }

    @Test func eventsLandTogetherAfterATick() async throws {
        let c = connection()
        c.subscribe(chatId: "c")
        for i in 1...50 { c._applyForTests(.event(ev(i, .assistant(id: "a\(i)", text: "\(i)")))) }
        #expect((c.transcripts["c"]?.events.count ?? 0) == 0)
        try await Task.sleep(for: .milliseconds(80))
        #expect(c.transcripts["c"]?.events.count == 50)
        #expect(c.transcripts["c"]?.lastSeq == 50)
    }

    @Test func aDeltaArrivingMidBatchStaysAfterTheEventsBeforeIt() async throws {
        let c = connection()
        c.subscribe(chatId: "c")
        c._applyForTests(.event(ev(1, .user(id: "u1", text: "go", images: [], from: .ios, replyTo: nil))))
        c._applyForTests(.event(ev(2, .assistant(id: "a1", text: "done"))))
        // The next reply starts streaming: what was held goes in first, so the
        // finished "done" does not land after this typing tail and clear it.
        c._applyForTests(.delta(chatId: "c", text: "Now"))
        #expect(c.transcripts["c"]?.events.count == 2)
        try await Task.sleep(for: .milliseconds(80))
        #expect(c.stream("c").text == "Now")
        #expect(c.transcripts["c"]?.events.count == 2)
    }
}
