import Foundation

// Mirrors superagent-desktop/app/src/shared/companion-protocol.ts.
// Both test suites decode the same JSON fixtures, so drift fails CI on either side.

let protocolVersion = 1

// MARK: - Events

struct DiffHunk: Codable, Hashable, Sendable {
    var removed: [String]
    var added: [String]
}

struct ImageMeta: Codable, Hashable, Sendable {
    var mediaType: String
    var size: Int
}

enum ApprovalOutcome: String, Codable, Sendable { case approved, denied, expired }
enum Origin: String, Codable, Sendable { case desktop, ios }

/// The message a reply answers, WhatsApp-style.
///
/// It travels beside the text, not inside it: the Mac turns it into a blockquote
/// for the agent to read, but a device drawing the conversation wants the quote
/// as its own thing so it can show a chip, and wants the text to be only what
/// the person typed.
struct ReplyQuote: Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var role: Role
    var text: String
}

enum WireEventData: Hashable, Sendable {
    case user(id: String, text: String, images: [ImageMeta], from: Origin, replyTo: ReplyQuote?)
    case assistant(id: String, text: String)
    case thinking(id: String, text: String)
    case tool(id: String, name: String, detail: String, task: TaskInfo?)
    case toolResult(toolId: String, ok: Bool, summary: String)
    case diff(id: String, file: String, hunks: [DiffHunk])
    /// `contextTokens` is the live context when the turn ended — what the next
    /// prompt will carry. `tokens` sums the whole turn, which can exceed the
    /// window several times over; the meter wants the former.
    case turnEnd(ok: Bool, subtype: String, costUsd: Double?, tokens: Int?, contextTokens: Int?)
    case session(claudeSessionId: String, model: String?, commands: [String])
    case notice(text: String)
    /// A file the agent handed over: a generated PDF, an export, a report.
    case file(id: String, path: String, name: String, workspaceId: String?, size: Int?, mediaType: String?)
    case approval(id: String, toolName: String, preview: String, approvalKind: String, expiresAt: Double)
    case approvalEnd(id: String, outcome: ApprovalOutcome, by: Origin)
    /// A kind this build doesn't know. Kept so an old app never chokes on a new Mac.
    case unknown(kind: String)

    var kind: String {
        switch self {
        case .user: "user"
        case .assistant: "assistant"
        case .thinking: "thinking"
        case .tool: "tool"
        case .toolResult: "tool_result"
        case .diff: "diff"
        case .turnEnd: "turn_end"
        case .session: "session"
        case .notice: "notice"
        case .file: "file"
        case .approval: "approval"
        case .approvalEnd: "approval_end"
        case .unknown(let k): k
        }
    }
}

extension WireEventData: Codable {
    private enum K: String, CodingKey {
        case kind, id, text, images, from, name, detail, toolId, ok, summary, file, hunks, path, size, mediaType, workspaceId, replyTo
        case subtype, costUsd, tokens, contextTokens, claudeSessionId, model, commands, toolName, preview, approvalKind, expiresAt, outcome, by, task
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "user":
            self = .user(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                images: try c.decodeIfPresent([ImageMeta].self, forKey: .images) ?? [],
                from: try c.decodeIfPresent(Origin.self, forKey: .from) ?? .desktop,
                replyTo: try c.decodeIfPresent(ReplyQuote.self, forKey: .replyTo))
        case "assistant":
            self = .assistant(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text))
        case "thinking":
            self = .thinking(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text))
        case "tool":
            self = .tool(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                detail: try c.decodeIfPresent(String.self, forKey: .detail) ?? "",
                task: try c.decodeIfPresent(TaskInfo.self, forKey: .task))
        case "tool_result":
            self = .toolResult(
                toolId: try c.decode(String.self, forKey: .toolId),
                ok: try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true,
                summary: try c.decodeIfPresent(String.self, forKey: .summary) ?? "")
        case "diff":
            self = .diff(
                id: try c.decode(String.self, forKey: .id),
                file: try c.decodeIfPresent(String.self, forKey: .file) ?? "",
                hunks: try c.decodeIfPresent([DiffHunk].self, forKey: .hunks) ?? [])
        case "turn_end":
            self = .turnEnd(
                ok: try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true,
                subtype: try c.decodeIfPresent(String.self, forKey: .subtype) ?? "success",
                costUsd: try c.decodeIfPresent(Double.self, forKey: .costUsd),
                tokens: try c.decodeIfPresent(Int.self, forKey: .tokens),
                contextTokens: try c.decodeIfPresent(Int.self, forKey: .contextTokens))
        case "session":
            self = .session(
                claudeSessionId: try c.decode(String.self, forKey: .claudeSessionId),
                model: try c.decodeIfPresent(String.self, forKey: .model),
                commands: try c.decodeIfPresent([String].self, forKey: .commands) ?? [])
        case "file":
            // Decoded a field at a time: as one call the type checker gave up.
            let fileId = try c.decode(String.self, forKey: .id)
            let filePath = try c.decode(String.self, forKey: .path)
            let fileName = try c.decode(String.self, forKey: .name)
            let fileWs = try c.decodeIfPresent(String.self, forKey: .workspaceId)
            let fileSize = try c.decodeIfPresent(Int.self, forKey: .size)
            let fileType = try c.decodeIfPresent(String.self, forKey: .mediaType)
            self = .file(id: fileId, path: filePath, name: fileName,
                         workspaceId: fileWs, size: fileSize, mediaType: fileType)
        case "notice":
            self = .notice(text: try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "approval":
            self = .approval(
                id: try c.decode(String.self, forKey: .id),
                toolName: try c.decodeIfPresent(String.self, forKey: .toolName) ?? "",
                preview: try c.decodeIfPresent(String.self, forKey: .preview) ?? "",
                approvalKind: try c.decodeIfPresent(String.self, forKey: .approvalKind) ?? "guardrail",
                expiresAt: try c.decodeIfPresent(Double.self, forKey: .expiresAt) ?? 0)
        case "approval_end":
            self = .approvalEnd(
                id: try c.decode(String.self, forKey: .id),
                outcome: try c.decodeIfPresent(ApprovalOutcome.self, forKey: .outcome) ?? .expired,
                by: try c.decodeIfPresent(Origin.self, forKey: .by) ?? .desktop)
        default:
            self = .unknown(kind: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case let .user(id, text, images, from, replyTo):
            try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
            if !images.isEmpty { try c.encode(images, forKey: .images) }
            try c.encode(from, forKey: .from)
            try c.encodeIfPresent(replyTo, forKey: .replyTo)
        case let .assistant(id, text), let .thinking(id, text):
            try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
        case let .tool(id, name, detail, task):
            try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(detail, forKey: .detail)
            try c.encodeIfPresent(task, forKey: .task)
        case let .toolResult(toolId, ok, summary):
            try c.encode(toolId, forKey: .toolId); try c.encode(ok, forKey: .ok); try c.encode(summary, forKey: .summary)
        case let .file(id, path, name, workspaceId, size, mediaType):
            try c.encode(id, forKey: .id)
            try c.encode(path, forKey: .path)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(workspaceId, forKey: .workspaceId)
            try c.encodeIfPresent(size, forKey: .size)
            try c.encodeIfPresent(mediaType, forKey: .mediaType)
        case let .diff(id, file, hunks):
            try c.encode(id, forKey: .id); try c.encode(file, forKey: .file); try c.encode(hunks, forKey: .hunks)
        case let .turnEnd(ok, subtype, costUsd, tokens, contextTokens):
            try c.encode(ok, forKey: .ok); try c.encode(subtype, forKey: .subtype)
            try c.encodeIfPresent(costUsd, forKey: .costUsd); try c.encodeIfPresent(tokens, forKey: .tokens); try c.encodeIfPresent(contextTokens, forKey: .contextTokens)
        case let .session(sid, model, commands):
            try c.encode(sid, forKey: .claudeSessionId); try c.encodeIfPresent(model, forKey: .model)
            if !commands.isEmpty { try c.encode(commands, forKey: .commands) }
        case let .notice(text):
            try c.encode(text, forKey: .text)
        case let .approval(id, toolName, preview, approvalKind, expiresAt):
            try c.encode(id, forKey: .id); try c.encode(toolName, forKey: .toolName)
            try c.encode(preview, forKey: .preview); try c.encode(approvalKind, forKey: .approvalKind)
            try c.encode(expiresAt, forKey: .expiresAt)
        case let .approvalEnd(id, outcome, by):
            try c.encode(id, forKey: .id); try c.encode(outcome, forKey: .outcome); try c.encode(by, forKey: .by)
        case .unknown:
            break
        }
    }
}

struct WireEvent: Codable, Hashable, Sendable, Identifiable {
    var chatId: String
    var seq: Int
    var ts: Double
    var data: WireEventData
    var id: String { "\(chatId)#\(seq)" }
}

// MARK: - Summaries

enum WorkspaceStatus: String, Codable, Sendable {
    case idle, working
    case needsYou = "needs-you"
}

struct WireWorkspace: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var path: String
    var kind: String
    var status: WorkspaceStatus
    var branch: String?
    var browserUrl: String?
    var subrepos: [WireSubrepo]?

    var isBrowser: Bool { kind == "browser" }
    var isComputer: Bool { kind == "desktop" }
    /// Host of a browser project, for its favicon and a short label.
    var host: String? { browserUrl.flatMap { URL(string: $0)?.host }?.replacingOccurrences(of: "www.", with: "") }
}

struct WireSubrepo: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var path: String
    var branch: String?
    var id: String { path }
}

struct WireDir: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var path: String
    var repo: Bool
    var id: String { path }
}

struct WireGroup: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var color: String
    var workspaces: [WireWorkspace]
}

struct WireChat: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var workspaceId: String
    var title: String?
    var updatedAt: Double
    var live: Bool
    var preview: String?
    /// Which copy of the project this chat is in: "" for the project folder
    /// itself, otherwise the worktree's path. nil from a Mac too old to say,
    /// which is the only reason opening a project has a guess in it at all.
    var cwd: String?
    /// Waiting for its first message to cut its branch. It has no cwd yet,
    /// exactly like the folder's own chat, so this is what tells them apart.
    var pending: Bool?
    /// Which agent this conversation runs on — "claude" or "codex". The phone's
    /// model and mode pickers are Claude Code's, so a conversation on Codex must
    /// not be sent them: they are not a bad setting, they are a CLI that refuses
    /// to start. nil from a Mac too old to say.
    var provider: String?
    var isCodex: Bool { provider == "codex" }
    /// The conversation in the project folder — what the project row opens.
    /// The same test the Mac's sidebar makes: in the folder, and staying there.
    var isFolderChat: Bool { cwd == "" && pending != true }
}

struct WireMachine: Codable, Hashable, Sendable {
    var name: String
    var appVersion: String
    var protocolVersion: Int
    enum CodingKeys: String, CodingKey { case name, appVersion, protocolVersion = "protocol" }
}

// MARK: - Frames

struct RpcError: Codable, Hashable, Sendable, LocalizedError {
    var code: String
    var message: String
    var errorDescription: String? { message }
}

/// Mac → phone. `res` carries its result as raw JSON so each call site decodes what it expects.
enum ServerFrame: Sendable {
    case welcome(machine: WireMachine, tree: [WireGroup], chats: [WireChat])
    case paired(token: String, machine: WireMachine)
    case bye(reason: String)
    case event(WireEvent)
    case delta(chatId: String, text: String)
    case status(workspaceId: String, status: WorkspaceStatus)
    case chats([WireChat])
    case browser(WireBrowser)
    case simulator(WireSimulator)
    /// The agent called `open_file`: show this file, as the Mac just did.
    case openFile(workspaceId: String, path: String, chatId: String?)
    case res(id: String, result: Result<Data, RpcError>)
    case pong
    case unknown(t: String)
}

extension ServerFrame: Decodable {
    private enum K: String, CodingKey { case t, machine, tree, chats, token, reason, event, chatId, text, workspaceId, status, id, ok, result, error, browser, simulator, path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "welcome":
            self = .welcome(
                machine: try c.decode(WireMachine.self, forKey: .machine),
                tree: try c.decodeIfPresent([WireGroup].self, forKey: .tree) ?? [],
                chats: try c.decodeIfPresent([WireChat].self, forKey: .chats) ?? [])
        case "paired":
            self = .paired(token: try c.decode(String.self, forKey: .token), machine: try c.decode(WireMachine.self, forKey: .machine))
        case "bye":
            self = .bye(reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "")
        case "event":
            self = .event(try c.decode(WireEvent.self, forKey: .event))
        case "delta":
            self = .delta(chatId: try c.decode(String.self, forKey: .chatId), text: try c.decode(String.self, forKey: .text))
        case "status":
            self = .status(workspaceId: try c.decode(String.self, forKey: .workspaceId), status: try c.decode(WorkspaceStatus.self, forKey: .status))
        case "browser":
            self = .browser(try c.decode(WireBrowser.self, forKey: .browser))
        case "simulator":
            self = .simulator(try c.decode(WireSimulator.self, forKey: .simulator))
        case "chats":
            self = .chats(try c.decode([WireChat].self, forKey: .chats))
        case "openFile":
            self = .openFile(workspaceId: try c.decode(String.self, forKey: .workspaceId),
                             path: try c.decode(String.self, forKey: .path),
                             chatId: try c.decodeIfPresent(String.self, forKey: .chatId))
        case "res":
            let id = try c.decode(String.self, forKey: .id)
            if try c.decode(Bool.self, forKey: .ok) {
                // Re-encode the raw result so callers can decode their own type.
                let raw = try c.decodeIfPresent(JSONValue.self, forKey: .result) ?? .null
                self = .res(id: id, result: .success(try JSONEncoder().encode(raw)))
            } else {
                self = .res(id: id, result: .failure(try c.decode(RpcError.self, forKey: .error)))
            }
        case "pong":
            self = .pong
        default:
            self = .unknown(t: t)
        }
    }
}

struct DeviceInfo: Codable, Sendable {
    var id: String
    var name: String
    var model: String
    var pushToken: String?
}

/// Phone → Mac.
enum ClientFrame: Encodable, Sendable {
    case hello(device: String, token: String, app: String)
    case pair(device: DeviceInfo)
    case subscribe(chatId: String, afterSeq: Int)
    case unsubscribe(chatId: String)
    case req(id: String, method: String, params: JSONValue?)
    case ping

    private enum K: String, CodingKey { case t, v, device, token, app, chatId, afterSeq, id, method, params }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case let .hello(device, token, app):
            try c.encode("hello", forKey: .t); try c.encode(protocolVersion, forKey: .v)
            try c.encode(device, forKey: .device); try c.encode(token, forKey: .token); try c.encode(app, forKey: .app)
        case let .pair(device):
            try c.encode("pair", forKey: .t); try c.encode(device, forKey: .device)
        case let .subscribe(chatId, afterSeq):
            try c.encode("subscribe", forKey: .t); try c.encode(chatId, forKey: .chatId); try c.encode(afterSeq, forKey: .afterSeq)
        case let .unsubscribe(chatId):
            try c.encode("unsubscribe", forKey: .t); try c.encode(chatId, forKey: .chatId)
        case let .req(id, method, params):
            try c.encode("req", forKey: .t); try c.encode(id, forKey: .id); try c.encode(method, forKey: .method)
            try c.encodeIfPresent(params, forKey: .params)
        case .ping:
            try c.encode("ping", forKey: .t)
        }
    }
}

// MARK: - Pairing

struct PairPayload: Codable, Sendable, Hashable, Identifiable {
    var v: Int
    var name: String
    var relay: String
    var m: String
    var k: String
    var id: String { m + k }

    /// Parses `superagent://pair#<base64url json>` (what the QR and the copied link contain).
    static func parse(_ text: String) -> PairPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.range(of: "#") else { return nil }
        let b64 = String(trimmed[hash.upperBound...])
        guard let data = Data(base64URL: b64) else { return nil }
        return try? JSONDecoder().decode(PairPayload.self, from: data)
    }

    var secret: Data? { Data(base64URL: k) }
}

// MARK: - Loose JSON (for RPC params/results)

enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension Data {
    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Phase 2 payloads

/// What a planning tool call said (TodoWrite, TaskCreate, TaskUpdate).
struct TaskInfo: Codable, Hashable, Sendable {
    struct Todo: Codable, Hashable, Sendable {
        var text: String
        var status: String
    }
    var todos: [Todo]?
    var subject: String?
    var description: String?
    var taskId: String?
    var status: String?
}

/// What a conversation has open in the Mac's browser pane.
struct WireBrowser: Codable, Hashable, Sendable {
    var chatId: String
    var open: Bool
    var url: String
    var title: String
    var canGoBack: Bool
    var canGoForward: Bool
    var loading: Bool
}

/// What today has cost on the relay, as the relay itself reports it.
struct RelayUsage: Sendable, Equatable {
    var day: String
    var bytes: Int
    var limit: Int

    var fraction: Double { limit > 0 ? min(1, Double(bytes) / Double(limit)) : 0 }

    /// "12 MB of 500 MB today" — megabytes, because that is the unit of the
    /// budget and of the thing that spends it.
    var summary: String {
        let used = bytes / 1_000_000
        let cap = limit / 1_000_000
        return "\(used) MB of \(cap) MB today"
    }
}

/// The iOS Simulator a conversation has open on the Mac.
/// One checkout of a project: the folder you opened, or a branch cut from it.
/// The Mac's sidebar is a row per one of these, so this one is too.
struct WireWorktree: Codable, Hashable, Sendable, Identifiable {
    var path: String
    var branch: String?
    /// The folder the project was opened as, rather than a branch cut from it.
    var main: Bool
    /// Where this branch merges home to. Nil for main.
    var base: String?
    /// The conversation happening in it, when there is one.
    var chatId: String?
    var chatTitle: String?

    var id: String { path }
    /// What the row calls itself when there is no conversation in it yet.
    var label: String { branch ?? (path as NSString).lastPathComponent }
}

struct WireSimulator: Codable, Hashable, Sendable {
    var chatId: String
    var open: Bool
    var udid: String
    var device: String
}

/// One still of that device, as the Mac's own pane draws it.
struct WireSimulatorShot: Codable, Sendable {
    var udid: String
    var device: String
    /// A whole `data:image/jpeg;base64,…` URL. Empty when `unchanged`.
    var url: String
    /// Byte-identical to the last frame we were sent, so it was not sent again.
    var unchanged: Bool?
}

struct WireBrowserShot: Codable, Sendable {
    var url: String
    var title: String
    var canGoBack: Bool
    var canGoForward: Bool
    var width: Int
    var height: Int
    /// Empty when `unchanged`.
    var jpeg: String
    /// Byte-identical to the last frame we were sent, so it was not sent again.
    var unchanged: Bool?
}

/// `chat.image`: the Mac's thumbnail for one picture on one message.
struct WireImage: Decodable, Sendable {
    var messageId: String
    var index: Int
    var mediaType: String
    var data: String
}

/// `files.chunk`: one slice of a file's bytes, base64, indexed from 0.
struct WireFileChunk: Decodable, Sendable {
    var path: String
    var index: Int
    var chunks: Int
    var data: String
}

enum WireFileContent: Decodable, Sendable {
    case text(path: String, size: Int, text: String, truncated: Bool)
    case image(path: String, size: Int, mediaType: String, data: String)
    /// A PDF the phone renders itself, so the text stays selectable and
    /// searchable. The bytes do not ride along: the relay caps a frame at 1 MB,
    /// so they come in `chunks` pulls of `files.chunk`.
    case pdf(path: String, size: Int, chunks: Int)
    case binary(path: String, size: Int)

    private enum K: String, CodingKey { case kind, path, size, text, truncated, mediaType, data, chunks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let path = try c.decode(String.self, forKey: .path)
        let size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        switch try c.decode(String.self, forKey: .kind) {
        case "text":
            self = .text(path: path, size: size, text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                         truncated: try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false)
        case "image":
            self = .image(path: path, size: size, mediaType: try c.decodeIfPresent(String.self, forKey: .mediaType) ?? "image/jpeg",
                          data: try c.decodeIfPresent(String.self, forKey: .data) ?? "")
        case "pdf":
            self = .pdf(path: path, size: size, chunks: try c.decodeIfPresent(Int.self, forKey: .chunks) ?? 0)
        default:
            self = .binary(path: path, size: size)
        }
    }
}

struct WireFileList: Decodable, Sendable {
    var root: String
    var files: [String]
}

struct WireBackgroundTask: Codable, Hashable, Sendable, Identifiable {
    var chatId: String
    var toolUseId: String
    var command: String
    var description: String?
    var startedAt: Double
    var output: String?
    var manual: Bool?
    var id: String { toolUseId }
}

struct WireBranch: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var current: Bool
    var worktree: String?
    var id: String { name }
}

struct WireSearchHit: Codable, Hashable, Sendable, Identifiable {
    var chatId: String
    var workspaceId: String
    var title: String?
    var ts: Double
    var role: String
    var snippet: String
    var id: String { chatId + "/" + role }
}

enum CardStatus: String, Codable, CaseIterable, Sendable {
    case todo, doing, testing, done
    var label: String {
        switch self { case .todo: "Todo"; case .doing: "Doing"; case .testing: "Testing"; case .done: "Done" }
    }
}

struct WireCard: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var workspaceId: String
    var title: String
    var body: String
    var status: CardStatus
    var chatId: String?
    var branch: String?
    var images: [String]
    var tags: [String]
    var position: Double
    var createdAt: Double
    var updatedAt: Double
}

struct WireRoutine: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var workspaceId: String
    var prompt: String
    var intervalMs: Double
    var enabled: Int
    var nextRunAt: Double
    var lastRunAt: Double?
    var lastRunStatus: String?
    var lastRunSummary: String?
    var runCount: Int?
    var lastRunTokens: Int?
    var isEnabled: Bool { enabled != 0 }
}
