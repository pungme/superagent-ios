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
        var closed: Bool { lock.withLock { _closed } }
        var sent: Int { lock.withLock { _sent } }
        init(emit: @escaping @Sendable (RelayTransport.Event) -> Void) { self.emit = emit }
        func connect(relay: String, machineId: String) {}
        func send(_ text: String) { lock.withLock { _sent += 1 } }
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
}
