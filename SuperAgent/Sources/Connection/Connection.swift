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
    /// Messages this phone has sent that the Mac hasn't echoed back yet. They
    /// render immediately; the echo (a `user` event with our id) retires them.
    var outbox: [Outgoing] = []

    mutating func apply(_ e: WireEvent) -> Bool {
        // Gaps mean we missed something; the caller re-subscribes from lastSeq.
        guard e.seq == lastSeq + 1 else { return e.seq <= lastSeq }
        events.append(e)
        lastSeq = e.seq
        switch e.data {
        case .assistant, .turnEnd, .notice: streaming = ""
        case .user(let id, _, _, _): outbox.removeAll { $0.id == id }
        default: break
        }
        return true
    }
}

/// A message on its way to the Mac. Shown as a bubble the moment Send is
/// tapped; queued while the link is down, retried on demand if it fails.
struct Outgoing: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable { case queued, sending, failed(String) }
    struct Image: Hashable, Sendable { let mediaType: String; let data: Data }

    let id: String
    let chatId: String
    let text: String
    let images: [Image]
    let ts: Double
    let model: String?
    let mode: String?
    var status: Status = .queued
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
    /// Slash commands the agent reported for a chat's session (for the "/" menu).
    private(set) var commands: [String: [String]] = [:]
    /// What each conversation has open in the Mac's browser pane.
    private(set) var browsers: [String: WireBrowser] = [:]

    private var transport: RelayTransport?
    private var sealer: Sealer
    private var opener: Opener
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var attempt = 0
    private var wantConnected = false
    private var pingTask: Task<Void, Never>?
    private var lastPong = Date()

    init(machine: PairedMachine) {
        self.machine = machine
        let keys = DeviceKeys(secret: machine.secret, machineId: machine.id)
        sealer = Sealer(key: keys.p2m, aad: aad(machineId: machine.id, direction: .p2m))
        opener = Opener(key: keys.m2p, aad: aad(machineId: machine.id, direction: .m2p))
        // Last known picture of the Mac, so there is something to read before
        // (or without) a connection.
        info = OfflineCache.load(machine.id, "machine", as: WireMachine.self)
        tree = OfflineCache.load(machine.id, "tree", as: [WireGroup].self) ?? []
        chats = OfflineCache.load(machine.id, "chats", as: [WireChat].self)?.map { var c = $0; c.live = false; return c } ?? []
    }

    private var transcriptSaves: [String: Task<Void, Never>] = [:]

    /// Write a chat's recent events a moment after they settle (not per frame).
    private func scheduleTranscriptSave(_ chatId: String) {
        transcriptSaves[chatId]?.cancel()
        transcriptSaves[chatId] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, let t = self.transcripts[chatId] else { return }
            OfflineCache.save(self.machine.id, "chat-" + chatId, Array(t.events.suffix(OfflineCache.transcriptLimit)))
        }
    }

    // MARK: Lifecycle

    func connect() {
        wantConnected = true
        reconnectTask?.cancel()
        open()
    }

    func disconnect() {
        browsers.removeAll()
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
            OfflineCache.save(machine.id, "machine", machineInfo)
            OfflineCache.save(machine.id, "tree", tree)
            OfflineCache.save(machine.id, "chats", chats)
            onChatsChanged?()
            state = .connected
            lastError = nil
            // Resubscribe to whatever we were watching, from where we left off.
            for (chatId, t) in transcripts where !t.subscribed {
                send(.subscribe(chatId: chatId, afterSeq: t.lastSeq))
                transcripts[chatId]?.subscribed = true
            }
            startPing()
            flushOutbox()
        case .paired:
            break // pairing is handled by PairFlow, not here
        case .bye(let reason):
            lastError = reason
            state = .failed(reason)
            wantConnected = reason == "version" ? false : wantConnected
        case .event(let e):
            if case let .session(_, _, cmds) = e.data, !cmds.isEmpty { commands[e.chatId] = cmds }
            var t = transcripts[e.chatId] ?? Transcript()
            if !t.apply(e) {
                // Gap: ask again from what we have.
                send(.subscribe(chatId: e.chatId, afterSeq: t.lastSeq))
            }
            transcripts[e.chatId] = t
            scheduleTranscriptSave(e.chatId)
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
        case .browser(let b):
            if b.open { browsers[b.chatId] = b } else { browsers[b.chatId] = nil }
        case .chats(let list):
            chats = list
            OfflineCache.save(machine.id, "chats", list)
            onChatsChanged?()
        case let .res(id, result):
            if let c = pending.removeValue(forKey: id) {
                switch result {
                case .success(let d): c.resume(returning: d)
                case .failure(let e): c.resume(throwing: e)
                }
            }
        case .pong:
            lastPong = Date()
        case .unknown:
            break
        }
    }

    private func startPing() {
        pingTask?.cancel()
        lastPong = Date()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self else { return }
                // Two unanswered pings: the socket is half-open (relay restarted,
                // network changed). Drop it and reconnect instead of waiting forever.
                if Date().timeIntervalSince(self.lastPong) > 60 {
                    self.lastError = "the relay stopped answering"
                    self.transport?.close()
                    return
                }
                self.send(.ping)
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
        var t = transcripts[chatId] ?? cachedTranscript(chatId) ?? Transcript()
        if state == .connected, !t.subscribed {
            send(.subscribe(chatId: chatId, afterSeq: t.lastSeq))
            t.subscribed = true
        }
        transcripts[chatId] = t
    }

    /// A chat's recent events from the last time it was open; the Mac fills in
    /// everything after `lastSeq` on subscribe.
    private func cachedTranscript(_ chatId: String) -> Transcript? {
        guard let events = OfflineCache.load(machine.id, "chat-" + chatId, as: [WireEvent].self), !events.isEmpty else { return nil }
        var t = Transcript()
        t.events = events
        t.lastSeq = events.last?.seq ?? 0
        return t
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
                self?.timeOut(id)
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

    /// Queue a message for the Mac. Returns at once; the bubble appears in the
    /// transcript's outbox and is delivered now or as soon as the link is back.
    func sendMessage(chatId: String, text: String, images: [(mediaType: String, data: Data)] = [],
                     model: String? = nil, mode: String? = nil) {
        let msg = Outgoing(id: "L-" + UUID().uuidString.prefix(8), chatId: chatId, text: text,
                           images: images.map { Outgoing.Image(mediaType: $0.mediaType, data: $0.data) },
                           ts: Date().timeIntervalSince1970 * 1000, model: model, mode: mode)
        var t = transcripts[chatId] ?? Transcript()
        t.outbox.append(msg)
        transcripts[chatId] = t
        Task { await deliver(chatId: chatId, id: msg.id) }
    }

    func retry(chatId: String, id: String) {
        setOutgoing(chatId: chatId, id: id, status: .queued)
        Task { await deliver(chatId: chatId, id: id) }
    }

    func discard(chatId: String, id: String) {
        transcripts[chatId]?.outbox.removeAll { $0.id == id }
    }

    private func setOutgoing(chatId: String, id: String, status: Outgoing.Status) {
        guard var t = transcripts[chatId], let i = t.outbox.firstIndex(where: { $0.id == id }) else { return }
        t.outbox[i].status = status
        transcripts[chatId] = t
    }

    private func deliver(chatId: String, id: String) async {
        // Not connected: it stays queued and goes out on the next welcome.
        guard state == .connected, let msg = transcripts[chatId]?.outbox.first(where: { $0.id == id }) else { return }
        setOutgoing(chatId: chatId, id: id, status: .sending)
        var params: [String: JSONValue] = [
            "chatId": .string(chatId),
            "text": .string(msg.text),
            "localId": .string(msg.id)
        ]
        if let m = msg.model { params["model"] = .string(m) }
        if let m = msg.mode { params["permissionMode"] = .string(m) }
        if !msg.images.isEmpty {
            params["images"] = .array(msg.images.map { .object(["mediaType": .string($0.mediaType), "data": .string($0.data.base64EncodedString())]) })
        }
        do {
            _ = try await rpc("chat.send", .object(params))
            // The echo normally retires it before the response lands; make sure.
            discard(chatId: chatId, id: id)
        } catch {
            // The Mac may or may not have taken it if the link dropped mid-flight,
            // so never resend on our own — leave the choice to the person.
            setOutgoing(chatId: chatId, id: id, status: .failed(error.localizedDescription))
        }
    }

    private func flushOutbox() {
        for (chatId, t) in transcripts {
            for m in t.outbox where m.status == .queued {
                Task { await deliver(chatId: chatId, id: m.id) }
            }
        }
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

    func renameChat(chatId: String, title: String) async throws {
        _ = try await rpc("chat.rename", .object(["chatId": .string(chatId), "title": .string(title)]))
        chats = chats.map { var c = $0; if c.id == chatId { c.title = title }; return c }
    }

    func deleteChat(chatId: String) async throws {
        _ = try await rpc("chat.delete", .object(["chatId": .string(chatId)]))
        chats.removeAll { $0.id == chatId }
        transcripts[chatId] = nil
        OfflineCache.removeTranscript(machine.id, chatId: chatId)
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

// MARK: - Projects, files, board, routines, browser, search

extension Connection {
    /// Re-read the sidebar (after a checkout, say); `tree` updates in place.
    func refreshTree() async {
        if let t: [WireGroup] = try? await rpc("tree.list", as: [WireGroup].self) { tree = t; OfflineCache.save(machine.id, "tree", t) }
    }

    func searchChats(_ query: String) async throws -> [WireSearchHit] {
        try await rpc("chat.search", .object(["query": .string(query), "limit": .number(40)]), as: [WireSearchHit].self)
    }

    func listFiles(workspaceId: String) async throws -> WireFileList {
        try await rpc("files.list", .object(["workspaceId": .string(workspaceId)]), as: WireFileList.self)
    }

    func readFile(workspaceId: String, path: String) async throws -> WireFileContent {
        try await rpc("files.read", .object(["workspaceId": .string(workspaceId), "path": .string(path)]), as: WireFileContent.self)
    }

    func branches(workspaceId: String) async throws -> [WireBranch] {
        try await rpc("git.branches", .object(["workspaceId": .string(workspaceId)]), as: [WireBranch].self)
    }

    func checkout(workspaceId: String, branch: String) async throws {
        _ = try await rpc("git.checkout", .object(["workspaceId": .string(workspaceId), "branch": .string(branch)]))
        await refreshTree()
    }

    func listCards(workspaceId: String) async throws -> [WireCard] {
        try await rpc("board.list", .object(["workspaceId": .string(workspaceId)]), as: [WireCard].self)
    }

    func addCard(workspaceId: String, title: String, body: String, status: CardStatus) async throws -> WireCard {
        try await rpc("board.add", .object(["workspaceId": .string(workspaceId), "title": .string(title), "body": .string(body), "status": .string(status.rawValue)]), as: WireCard.self)
    }

    func updateCard(id: String, title: String? = nil, body: String? = nil, status: CardStatus? = nil) async throws -> WireCard {
        var p: [String: JSONValue] = ["id": .string(id)]
        if let title { p["title"] = .string(title) }
        if let body { p["body"] = .string(body) }
        if let status { p["status"] = .string(status.rawValue) }
        return try await rpc("board.update", .object(p), as: WireCard.self)
    }

    func moveCard(id: String, to status: CardStatus) async throws -> WireCard {
        try await rpc("board.move", .object(["id": .string(id), "status": .string(status.rawValue), "beforeId": .null]), as: WireCard.self)
    }

    func listRoutines() async throws -> [WireRoutine] {
        try await rpc("routines.list", nil, as: [WireRoutine].self)
    }

    func setRoutineEnabled(id: String, enabled: Bool) async throws {
        _ = try await rpc("routines.setEnabled", .object(["id": .string(id), "enabled": .bool(enabled)]))
    }

    func runRoutineNow(id: String) async throws {
        _ = try await rpc("routines.runNow", .object(["id": .string(id)]))
    }

    private struct TreeResult: Decodable { var workspaceId: String?; var groupId: String?; var tree: [WireGroup] }
    private func applyTree(_ r: TreeResult) { tree = r.tree; OfflineCache.save(machine.id, "tree", r.tree) }

    /// Add a folder on the Mac as a project (or focus it if it already is one). Returns its id.
    func addWorkspace(groupId: String, name: String, path: String) async throws -> String {
        let r = try await rpc("workspace.add", .object(["groupId": .string(groupId), "name": .string(name), "path": .string(path)]), as: TreeResult.self)
        applyTree(r)
        return r.workspaceId ?? ""
    }

    func createBrowserTab(url: String? = nil) async throws -> String {
        var p: [String: JSONValue] = [:]
        if let url { p["url"] = .string(url) }
        let r = try await rpc("workspace.createBrowser", .object(p), as: TreeResult.self)
        applyTree(r)
        return r.workspaceId ?? ""
    }

    func removeWorkspace(id: String) async throws {
        applyTree(try await rpc("workspace.remove", .object(["id": .string(id)]), as: TreeResult.self))
        chats.removeAll { $0.workspaceId == id }
    }

    func createGroup(name: String) async throws {
        applyTree(try await rpc("group.create", .object(["name": .string(name)]), as: TreeResult.self))
    }

    func renameGroup(id: String, name: String) async throws {
        applyTree(try await rpc("group.rename", .object(["id": .string(id), "name": .string(name)]), as: TreeResult.self))
    }

    func deleteGroup(id: String) async throws {
        applyTree(try await rpc("group.delete", .object(["id": .string(id)]), as: TreeResult.self))
    }

    func listDirs(path: String?) async throws -> (path: String, dirs: [WireDir]) {
        struct R: Decodable { var path: String; var dirs: [WireDir] }
        let r = try await rpc("fs.dirs", .object(path.map { ["path": .string($0)] } ?? [:]), as: R.self)
        return (r.path, r.dirs)
    }

    func browserOpen(chatId: String, url: String) async throws -> String {
        struct R: Decodable { var url: String }
        return try await rpc("browser.open", .object(["chatId": .string(chatId), "url": .string(url)]), as: R.self).url
    }

    func browserShot(chatId: String) async throws -> WireBrowserShot {
        try await rpc("browser.screenshot", .object(["chatId": .string(chatId), "maxWidth": .number(900)]), as: WireBrowserShot.self)
    }

    func browserNav(chatId: String, action: String) async throws {
        _ = try await rpc("browser.nav", .object(["chatId": .string(chatId), "action": .string(action)]))
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
}

#if DEBUG
// MARK: - Scroll harness
//
// Debug-only scaffolding so the transcript's scrolling can be exercised in the
// simulator without pairing a Mac. Launch with `-scrollHarness`. Lives in this
// file because `transcripts` has a private setter, and because the project file
// is checked in: a new source file would not be compiled without xcodegen.

extension Connection {
    @MainActor
    static func scrollHarness(chatId: String = "harness", turns: Int = 60) -> Connection {
        let machine = PairedMachine(id: "harness", name: "Harness", relay: "wss://example.invalid",
                                    deviceId: "harness-device", secret: Data(repeating: 7, count: 32),
                                    token: "harness", pairedAt: .now)
        let c = Connection(machine: machine)
        var t = Transcript()
        var seq = 0
        let now = Date().timeIntervalSince1970 * 1000
        for i in 0..<turns {
            seq += 1
            t.events.append(WireEvent(chatId: chatId, seq: seq, ts: now,
                                      data: .user(id: "u\(i)", text: "Question \(i + 1). Does the transcript stay at the end?",
                                                  images: [], from: .ios)))
            seq += 1
            // Deliberately uneven heights: a LazyVStack estimating uniform rows
            // is exactly what made the old scrollTo land on blank space.
            let body = String(repeating: "Reply \(i + 1) line. ", count: 3 + (i % 9) * 7)
            t.events.append(WireEvent(chatId: chatId, seq: seq, ts: now,
                                      data: .assistant(id: "a\(i)", text: body)))
            seq += 1
            t.events.append(WireEvent(chatId: chatId, seq: seq, ts: now,
                                      data: .turnEnd(ok: true, subtype: "success", costUsd: 0.0123, tokens: 900 + i)))
        }
        t.lastSeq = seq
        c.transcripts[chatId] = t
        // Pretend the Mac has a page open for this chat, so the docked mirror
        // above the transcript can be exercised too.
        c.browsers[chatId] = WireBrowser(chatId: chatId, open: true,
                                         url: "https://stripe.com/en-us", title: "Stripe",
                                         canGoBack: false, canGoForward: false, loading: false)
        return c
    }
}

#endif
