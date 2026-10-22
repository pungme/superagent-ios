import Testing
import Foundation
@testable import SuperAgent

/// The link to the Mac. "Stuck at connecting" came from here: the app opened a
/// second socket whenever it came back to the front, without closing the
/// first, and waited without limit for a welcome that could no longer open.
@MainActor
struct ConnectionLinkTests {
    /// A socket that goes nowhere: it records what happened to it, and the test
    /// says what arrives on it.
    final class FakeTransport: Transport, @unchecked Sendable {
        let emit: @Sendable (RelayTransport.Event) -> Void
        private let lock = NSLock()
        private var _closed = false
        private var _sent = 0
        private var _texts: [String] = []
        var closed: Bool { lock.withLock { _closed } }
        var sent: Int { lock.withLock { _sent } }
        /// Everything sent, still sealed.
        var texts: [String] { lock.withLock { _texts } }
        init(emit: @escaping @Sendable (RelayTransport.Event) -> Void) { self.emit = emit }
        func connect(relay: String, machineId: String) {}
        func send(_ text: String) { lock.withLock { _sent += 1; _texts.append(text) } }
        func close() { lock.withLock { _closed = true } }
    }
    final class Sockets: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [FakeTransport] = []
        func add(_ t: FakeTransport) { lock.withLock { all.append(t) } }
        var made: [FakeTransport] { lock.withLock { all } }
    }

    private let machine = PairedMachine(id: "link-\(UUID().uuidString)", name: "Mac", relay: "wss://example.invalid",
                                        deviceId: "d", secret: Data(repeating: 7, count: 32),
                                        token: "t", pairedAt: .now)

    private func connection() -> (Connection, Sockets) {
        let sockets = Sockets()
        let c = Connection(machine: machine)
        c._makeTransport = { emit in
            let t = FakeTransport(emit: emit)
            sockets.add(t)
            return t
        }
        return (c, sockets)
    }

    /// The Mac's welcome, sealed as the Mac seals it.
    private func welcome(salt: UInt8 = 1) throws -> String {
        final class Marker {}
        let url = try #require(Bundle(for: Marker.self).url(forResource: "frames", withExtension: "json"))
        let all = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let first = try #require((all["server"] as? [Any])?.first)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: first), as: UTF8.self)
        var mac = Sealer(key: DeviceKeys(secret: machine.secret, machineId: machine.id).m2p,
                         aad: aad(machineId: machine.id, direction: .m2p),
                         salt: Data(repeating: salt, count: 4))
        return try mac.seal(json)
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

    @Test func comingBackToTheFrontDoesNotOpenASecondSocket() async throws {
        let (c, sockets) = connection()
        c.connect()
        c.connect() // the app became active again before the first had answered
        #expect(sockets.made.count == 1)
        sockets.made[0].emit(.opened)
        sockets.made[0].emit(.text(try welcome()))
        await settle()
        #expect(c.state == .connected)
        c.connect() // and again once connected
        #expect(sockets.made.count == 1)
        #expect(sockets.made[0].closed == false)
        #expect(c.state == .connected)
    }

    @Test func aSocketThatWasReplacedCannotDisturbTheNewOne() async throws {
        let (c, sockets) = connection()
        c.connect()
        c.disconnect()
        c.connect()
        #expect(sockets.made.count == 2)
        #expect(sockets.made[0].closed)
        let (old, new) = (sockets.made[0], sockets.made[1])
        // A frame still on its way on the old socket, then the new one's welcome
        // (a different connection on the Mac, so a different salt).
        old.emit(.text(try welcome(salt: 9)))
        new.emit(.opened)
        new.emit(.text(try welcome(salt: 2)))
        await settle()
        #expect(c.state == .connected)
        // The old socket finally closing is nothing to do with the link in use.
        old.emit(.closed(code: 1001, reason: "gone"))
        await settle()
        #expect(c.state == .connected)
        #expect(new.closed == false)
        #expect(sockets.made.count == 2)
    }

    @Test func aHelloTheMacNeverAnswersIsGivenUpOnAndTriedAgain() async throws {
        let (c, sockets) = connection()
        c._handshakeTimeout = .milliseconds(120)
        c.connect()
        sockets.made[0].emit(.opened) // the relay is there; the Mac says nothing
        try await Task.sleep(for: .milliseconds(300))
        #expect(sockets.made[0].closed)
        #expect(c.state == .connecting)
        #expect(c.lastError == "the Mac did not answer")
        // And it tries again by itself (the first wait is a second).
        try await Task.sleep(for: .milliseconds(1300))
        #expect(sockets.made.count == 2)
    }

    @Test func aLinkThatDiedWhileAwayIsNoticedOnReturn() async throws {
        let (c, sockets) = connection()
        c._aliveTimeout = .milliseconds(120)
        c.connect()
        sockets.made[0].emit(.opened)
        sockets.made[0].emit(.text(try welcome()))
        await settle()
        #expect(c.state == .connected)
        let before = sockets.made[0].sent
        c.connect() // back at the front: it asks, and nothing answers
        #expect(sockets.made[0].sent == before + 1)
        try await Task.sleep(for: .milliseconds(300))
        #expect(sockets.made[0].closed)
        #expect(c.state == .connecting)
    }

    /// What the phone has said to the Mac, opened as the Mac opens it: each
    /// frame's `t`, with the chat it names.
    private func said(_ socket: FakeTransport) throws -> [String] {
        try frames(socket).map { o in
            let t = o["t"] as? String ?? "?"
            return (o["chatId"] as? String).map { "\(t) \($0)" } ?? t
        }
    }

    private func frames(_ socket: FakeTransport) throws -> [[String: Any]] {
        var mac = Opener(key: DeviceKeys(secret: machine.secret, machineId: machine.id).p2m,
                         aad: aad(machineId: machine.id, direction: .p2m))
        var out: [[String: Any]] = []
        for sealed in socket.texts {
            let plain = mac.open(sealed)
            let opened = try #require(plain)
            out.append(try #require(JSONSerialization.jsonObject(with: Data(opened.utf8)) as? [String: Any]))
        }
        return out
    }

    /// Replying to a long answer of the agent's. Its whole text went as the
    /// quote, and a Mac refuses a quote over 4,000 characters — with it the
    /// message, so the reply sat on the phone marked as failed.
    @Test func aReplyToALongAnswerGoesWithAQuoteAnyMacTakes() async throws {
        let (c, socket) = try await connected()
        let long = String(repeating: "Step by step, here is the plan. 🙂 ", count: 300)
        c.sendMessage(chatId: "c", text: "do step two first", replyTo: ReplyQuote(role: .assistant, text: long))
        await settle()
        let send = try #require(try frames(socket).first { ($0["method"] as? String) == "chat.send" })
        let params = try #require(send["params"] as? [String: Any])
        #expect(params["text"] as? String == "do step two first")
        let quote = try #require(params["replyTo"] as? [String: Any])
        #expect(quote["role"] as? String == "assistant")
        let text = try #require(quote["text"] as? String)
        #expect(text.utf16.count <= 4_000)
        #expect(text.hasPrefix("Step by step, here is the plan."))
        // The bubble still shows what you picked, whole.
        #expect(c.transcripts["c"]?.outbox.first?.replyTo?.text == long)
    }

    private func connected() async throws -> (Connection, FakeTransport) {
        let (c, sockets) = connection()
        c.connect()
        let socket = sockets.made[0]
        socket.emit(.opened)
        socket.emit(.text(try welcome()))
        await settle()
        #expect(c.state == .connected)
        return (c, socket)
    }

    /// The conversation you are in, opened again from a notification about it.
    /// The new copy arrives before the old one says it has gone, and that late
    /// goodbye used to unsubscribe the chat still on screen: the Mac stopped
    /// sending it anything, and it sat on what it had until you left it.
    @Test func theSameChatOpenedTwiceStaysSubscribedWhenTheOldCopyLeaves() async throws {
        let (c, socket) = try await connected()
        c.subscribe(chatId: "c")      // the conversation you were in
        c.subscribe(chatId: "c")      // the same one, pushed by the notification
        c.unsubscribe(chatId: "c")    // the first copy's transition ends
        await settle()
        #expect(try said(socket).filter { $0.hasSuffix(" c") } == ["subscribe c"],
                "the chat on screen must not be unsubscribed on the Mac")
        #expect(c.transcripts["c"]?.subscribed == true)

        // Live text still reaches it…
        c._applyForTests(.delta(chatId: "c", text: "Still here"))
        await settle()
        #expect(c.stream("c").text == "Still here")
        // …and a missed event is still asked for again.
        c._applyForTests(.event(WireEvent(chatId: "c", seq: 1, ts: 1000, data: .assistant(id: "a1", text: "first"))))
        await settle()
        c._applyForTests(.event(WireEvent(chatId: "c", seq: 3, ts: 3000, data: .assistant(id: "a3", text: "two was lost"))))
        await settle()
        #expect(try said(socket).filter { $0.hasSuffix(" c") } == ["subscribe c", "subscribe c"])

        // Once the last copy goes, the Mac stops sending it.
        c.unsubscribe(chatId: "c")
        await settle()
        #expect(try said(socket).last == "unsubscribe c")
        #expect(c.transcripts["c"]?.subscribed == false)
    }

    /// Asked to catch up when the link comes back, a chat is not counted as
    /// shown twice — leaving it once still lets it go.
    @Test func catchingUpAfterAReconnectIsNotAnotherViewer() async throws {
        let (c, socket) = try await connected()
        c.subscribe(chatId: "c")
        c.catchUp(chatId: "c")
        c.unsubscribe(chatId: "c")
        await settle()
        #expect(try said(socket).filter { $0.hasSuffix(" c") } == ["subscribe c", "unsubscribe c"])
        // And a chat nothing shows is not subscribed by a catch-up.
        c.catchUp(chatId: "other")
        await settle()
        #expect(try said(socket).contains("subscribe other") == false)
    }
}
