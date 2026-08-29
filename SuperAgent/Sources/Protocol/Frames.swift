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

enum WireEventData: Hashable, Sendable {
    case user(id: String, text: String, images: [ImageMeta], from: Origin)
    case assistant(id: String, text: String)
    case thinking(id: String, text: String)
    case tool(id: String, name: String, detail: String)
    case toolResult(toolId: String, ok: Bool, summary: String)
    case diff(id: String, file: String, hunks: [DiffHunk])
    case turnEnd(ok: Bool, subtype: String, costUsd: Double?, tokens: Int?)
    case session(claudeSessionId: String, model: String?)
    case notice(text: String)
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
        case .approval: "approval"
        case .approvalEnd: "approval_end"
        case .unknown(let k): k
        }
    }
}

extension WireEventData: Codable {
    private enum K: String, CodingKey {
        case kind, id, text, images, from, name, detail, toolId, ok, summary, file, hunks
        case subtype, costUsd, tokens, claudeSessionId, model, toolName, preview, approvalKind, expiresAt, outcome, by
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
                from: try c.decodeIfPresent(Origin.self, forKey: .from) ?? .desktop)
        case "assistant":
            self = .assistant(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text))
        case "thinking":
            self = .thinking(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text))
        case "tool":
            self = .tool(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                detail: try c.decodeIfPresent(String.self, forKey: .detail) ?? "")
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
                tokens: try c.decodeIfPresent(Int.self, forKey: .tokens))
        case "session":
            self = .session(
                claudeSessionId: try c.decode(String.self, forKey: .claudeSessionId),
                model: try c.decodeIfPresent(String.self, forKey: .model))
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
        case let .user(id, text, images, from):
            try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
            if !images.isEmpty { try c.encode(images, forKey: .images) }
            try c.encode(from, forKey: .from)
        case let .assistant(id, text), let .thinking(id, text):
            try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
        case let .tool(id, name, detail):
            try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(detail, forKey: .detail)
        case let .toolResult(toolId, ok, summary):
            try c.encode(toolId, forKey: .toolId); try c.encode(ok, forKey: .ok); try c.encode(summary, forKey: .summary)
        case let .diff(id, file, hunks):
            try c.encode(id, forKey: .id); try c.encode(file, forKey: .file); try c.encode(hunks, forKey: .hunks)
        case let .turnEnd(ok, subtype, costUsd, tokens):
            try c.encode(ok, forKey: .ok); try c.encode(subtype, forKey: .subtype)
            try c.encodeIfPresent(costUsd, forKey: .costUsd); try c.encodeIfPresent(tokens, forKey: .tokens)
        case let .session(sid, model):
            try c.encode(sid, forKey: .claudeSessionId); try c.encodeIfPresent(model, forKey: .model)
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
    case res(id: String, result: Result<Data, RpcError>)
    case pong
    case unknown(t: String)
}

extension ServerFrame: Decodable {
    private enum K: String, CodingKey { case t, machine, tree, chats, token, reason, event, chatId, text, workspaceId, status, id, ok, result, error }

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
        case "chats":
            self = .chats(try c.decode([WireChat].self, forKey: .chats))
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
