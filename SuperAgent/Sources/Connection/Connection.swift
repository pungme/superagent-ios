import Foundation
import Observation
import UIKit

/// What the phone knows about one chat: its sequenced events plus the text
/// currently streaming (which is never persisted, only shown).
struct Transcript: Sendable {
    var events: [WireEvent] = []
    var lastSeq: Int = 0
    var streaming: String = ""
    var subscribed = false

    mutating func apply(_ e: WireEvent) -> Bool {
        // Gaps mean we missed something; the caller re-subscribes from lastSeq.
        guard e.seq == lastSeq + 1 else { return e.seq <= lastSeq }
        events.append(e)
        lastSeq = e.seq
        switch e.data {
        case .assistant, .turnEnd, .notice: streaming = ""
        default: break
        }
        return true
    }
}

/// The live link to one Mac. Foreground-only by design: assume it is dead every
/// time the app comes back, reconnect, and let `afterSeq` do the catching up.
@MainActor
@Observable
final class Connection {
    enum State: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case machineOffline
        case failed(String)
    }

    let machine: PairedMachine
    /// Fired after the Mac sends a fresh chat list (welcome or `chats`).
    var onChatsChanged: (() -> Void)?
    private(set) var state: State = .idle
    private(set) var info: WireMachine?
    private(set) var tree: [WireGroup] = []
    private(set) var chats: [WireChat] = []
    private(set) var transcripts: [String: Transcript] = [:]
    private(set) var lastError: String?

    private var transport: RelayTransport?
    private var sealer: Sealer
    private var opener: Opener
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var attempt = 0
    private var wantConnected = false
    private var pingTask: Task<Void, Never>?

    init(machine: PairedMachine) {
        self.machine = machine
        let keys = DeviceKeys(secret: machine.secret, machineId: machine.id)
        sealer = Sealer(key: keys.p2m, aad: aad(machineId: machine.id, direction: .p2m))
        opener = Opener(key: keys.m2p, aad: aad(machineId: machine.id, direction: .m2p))
    }

    // MARK: Lifecycle

    func connect() {
        wantConnected = true
        reconnectTask?.cancel()
        open()
    }

    func disconnect() {
        wantConnected = false
        reconnectTask?.cancel()
        pingTask?.cancel()
        transport?.close()
        transport = nil
        state = .idle
        for (_, c) in pending { c.resume(throwing: RpcError(code: "closed", message: "connection closed")) }
        pending.removeAll()
    }

    private func open() {
        guard wantConnected else { return }
        state = .connecting
        let keys = DeviceKeys(secret: machine.secret, machineId: machine.id)
        sealer = Sealer(key: keys.p2m, aad: aad(machineId: machine.id, direction: .p2m))
        opener = Opener(key: keys.m2p, aad: aad(machineId: machine.id, direction: .m2p))
        for k in transcripts.keys { transcripts[k]?.subscribed = false }
        let t = RelayTransport { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        transport = t
        t.connect(relay: machine.relay, machineId: machine.id)
    }

    private func handle(_ event: RelayTransport.Event) {
        switch event {
        case .opened:
            attempt = 0
            send(.hello(device: machine.deviceId, token: machine.token, app: "ios/\(Bundle.main.shortVersion)"))
        case .text(let text):
            if text.hasPrefix("{") {
                // Relay's own frames arrive in the clear.
                if text.contains("\"offline\"") { state = .machineOffline }
                return
            }
            guard let plain = opener.open(text) else { return }
            guard let data = plain.data(using: .utf8), let frame = try? JSONDecoder().decode(ServerFrame.self, from: data) else { return }
            apply(frame)
        case .closed(let code, let reason):
            transport = nil
            pingTask?.cancel()
            if state != .machineOffline {
                state = wantConnected ? .connecting : .idle
            }
            if !reason.isEmpty { lastError = reason }
            if code == 4404 { state = .machineOffline }
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard wantConnected else { return }
        reconnectTask?.cancel()
        let delay = min(30.0, pow(2.0, Double(min(attempt, 5)))) * (state == .machineOffline ? 3 : 1)
        attempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private func apply(_ frame: ServerFrame) {
        switch frame {
        case let .welcome(machineInfo, tree, chats):
            info = machineInfo
            self.tree = tree
            self.chats = chats
            onChatsChanged?()
            state = .connected
            lastError = nil
            // Resubscribe to whatever we were watching, from where we left off.
            for (chatId, t) in transcripts where !t.subscribed {
                send(.subscribe(chatId: chatId, afterSeq: t.lastSeq))
                transcripts[chatId]?.subscribed = true
            }
            startPing()
        case .paired:
            break // pairing is handled by PairFlow, not here
        case .bye(let reason):
            lastError = reason
            state = .failed(reason)
            wantConnected = reason == "version" ? false : wantConnected
        case .event(let e):
            var t = transcripts[e.chatId] ?? Transcript()
            if !t.apply(e) {
                // Gap: ask again from what we have.
                send(.subscribe(chatId: e.chatId, afterSeq: t.lastSeq))
            }
            transcripts[e.chatId] = t
        case let .delta(chatId, text):
            var t = transcripts[chatId] ?? Transcript()
            t.streaming += text
            transcripts[chatId] = t
        case let .status(workspaceId, status):
            tree = tree.map { g in
                var g = g
                g.workspaces = g.workspaces.map { w in
                    var w = w
                    if w.id == workspaceId { w.status = status }
                    return w
                }
                return g
            }
        case .chats(let list):
            chats = list
            onChatsChanged?()
        case let .res(id, result):
            if let c = pending.removeValue(forKey: id) {
                switch result {
                case .success(let d): c.resume(returning: d)
                case .failure(let e): c.resume(throwing: e)
                }
            }
        case .pong, .unknown:
            break
        }
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                await self?.send(.ping)
            }
        }
    }

    // MARK: Sending

    func send(_ frame: ClientFrame) {
        guard let transport, let json = try? JSONEncoder().encode(frame), let text = String(data: json, encoding: .utf8) else { return }
        guard let sealed = try? sealer.seal(text) else { return }
        transport.send(sealed)
    }

    func subscribe(chatId: String) {
        var t = transcripts[chatId] ?? Transcript()
        if state == .connected, !t.subscribed {
            send(.subscribe(chatId: chatId, afterSeq: t.lastSeq))
            t.subscribed = true
        }
        transcripts[chatId] = t
    }

    /// Call a method on the Mac and decode its result.
    func rpc<T: Decodable>(_ method: String, _ params: JSONValue? = nil, as type: T.Type = JSONValue.self) async throws -> T {
        guard state == .connected else { throw RpcError(code: "unavailable", message: "not connected") }
        let id = UUID().uuidString
        let data: Data = try await withCheckedThrowingContinuation { c in
            pending[id] = c
            send(.req(id: id, method: method, params: params))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                await self?.timeOut(id)
            }
        }
        if T.self == JSONValue.self, data.isEmpty { return JSONValue.null as! T }
        return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("null".utf8) : data)
    }

    private func timeOut(_ id: String) {
        if let c = pending.removeValue(forKey: id) {
            c.resume(throwing: RpcError(code: "timeout", message: "the Mac did not answer"))
        }
    }

    // MARK: Convenience

    func sendMessage(chatId: String, text: String, images: [(mediaType: String, data: Data)] = []) async throws {
        var params: [String: JSONValue] = [
            "chatId": .string(chatId),
            "text": .string(text),
            "localId": .string("L-" + UUID().uuidString.prefix(8))
        ]
        if !images.isEmpty {
            params["images"] = .array(images.map { .object(["mediaType": .string($0.mediaType), "data": .string($0.data.base64EncodedString())]) })
        }
        _ = try await rpc("chat.send", .object(params))
    }

    func interrupt(chatId: String) async throws {
        _ = try await rpc("chat.interrupt", .object(["chatId": .string(chatId)]))
    }

    func answerApproval(id: String, approve: Bool, trustRest: Bool = false) async throws {
        _ = try await rpc("approval.answer", .object(["id": .string(id), "approve": .bool(approve), "trustRest": .bool(trustRest)]))
    }

    func reportPresence(active: Bool, pushToken: String? = nil) {
        var params: [String: JSONValue] = ["active": .bool(active)]
        if let pushToken {
            params["pushToken"] = .string(pushToken)
            #if DEBUG
            params["pushEnv"] = .string("sandbox")
            #else
            params["pushEnv"] = .string("production")
            #endif
        }
        send(.req(id: UUID().uuidString, method: "device.presence", params: .object(params)))
    }

    func createChat(workspaceId: String) async throws -> String {
        struct R: Decodable { var chatId: String }
        let id = try await rpc("chat.create", .object(["workspaceId": .string(workspaceId)]), as: R.self).chatId
        // Show it at once; the Mac's `chats` frame will confirm shortly.
        if !chats.contains(where: { $0.id == id }) {
            chats.append(WireChat(id: id, workspaceId: workspaceId, title: nil, updatedAt: Date().timeIntervalSince1970 * 1000, live: false))
        }
        return id
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
}
