import Foundation

/// The transcript, regrouped the way the desktop shows it: each user message
/// starts a turn; inside a turn, runs of tool activity collapse into one
/// "steps" row between the assistant's messages.
struct Turn: Identifiable {
    let id: String
    var items: [TurnItem]
    var cost: Double?
    var tokens: Int?
    var startedAt: Double?
    var endedAt: Double?
    var duration: TimeInterval? {
        guard let s = startedAt, let e = endedAt, e >= s else { return nil }
        return (e - s) / 1000
    }
}

enum TurnItem: Identifiable {
    case event(WireEvent)
    case steps(StepGroup)

    var id: String {
        switch self {
        case .event(let e): e.id
        case .steps(let g): g.id
        }
    }
}

/// Consecutive tool calls, edits, results and thoughts.
struct StepGroup: Identifiable {
    let id: String
    var events: [WireEvent]

    var toolCount: Int { events.filter { if case .tool = $0.data { return true }; return false }.count }
    var editCount: Int { events.filter { if case .diff = $0.data { return true }; return false }.count }
    var failed: Int {
        events.filter { if case let .toolResult(_, ok, _) = $0.data { return !ok }; return false }.count
    }
    /// "Running ×3 · Reading ×2" — distinct verbs in first-seen order, like the desktop.
    var summary: String {
        var counts: [(String, Int)] = []
        for e in events {
            let verb: String?
            switch e.data {
            case .tool(_, let name, _, _): verb = StepGroup.verb(for: name)
            case .diff: verb = "Editing"
            default: verb = nil
            }
            guard let v = verb else { continue }
            if let i = counts.firstIndex(where: { $0.0 == v }) { counts[i].1 += 1 } else { counts.append((v, 1)) }
        }
        let parts = counts.prefix(3).map { $0.1 > 1 ? "\($0.0) ×\($0.1)" : $0.0 }
        return parts.joined(separator: " · ") + (counts.count > 3 ? " · …" : "")
    }

    static func verb(for tool: String) -> String {
        switch tool {
        case "Bash": return "Running"
        case "Read", "Glob", "Grep", "LS": return "Reading"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing"
        case "WebFetch", "WebSearch": return "Browsing"
        case "Task", "Agent": return "Delegating"
        case "TaskCreate", "TaskUpdate", "TodoWrite": return "Planning"
        default:
            if tool.hasPrefix("mcp__cove-browser__browser") { return "Browsing" }
            if tool.hasPrefix("mcp__cove-browser__sim") { return "Simulating" }
            if tool.hasPrefix("mcp__cove-browser__board") { return "Board" }
            return "Using tools"
        }
    }
}

enum TurnBuilder {
    static func build(_ events: [WireEvent]) -> [Turn] {
        var turns: [Turn] = []
        var current = Turn(id: "t0", items: [])
        var group: StepGroup?

        func closeGroup() {
            // Only results, no calls: nothing to show.
            if let g = group, g.events.contains(where: { $0.toolIdIfCall != nil || $0.isThinking }) { current.items.append(.steps(g)) }
            group = nil
        }
        func closeTurn() {
            closeGroup()
            if !current.items.isEmpty || current.tokens != nil { turns.append(current) }
        }

        // A tool's result can arrive after an approval settled in between; it
        // belongs with the call, not in a group of its own.
        func attachResult(_ e: WireEvent, toolId: String) -> Bool {
            if var g = group, g.events.contains(where: { $0.toolIdIfCall == toolId }) { g.events.append(e); group = g; return true }
            for (i, item) in current.items.enumerated().reversed() {
                if case var .steps(g) = item, g.events.contains(where: { $0.toolIdIfCall == toolId }) {
                    g.events.append(e); current.items[i] = .steps(g); return true
                }
            }
            return false
        }

        for e in events {
            switch e.data {
            case .user:
                closeTurn()
                current = Turn(id: e.id, items: [.event(e)], startedAt: e.ts)
            case .toolResult(let toolId, _, _):
                if !attachResult(e, toolId: toolId) {
                    if group == nil { group = StepGroup(id: "g-\(e.id)", events: []) }
                    group!.events.append(e)
                }
            case .tool, .diff, .thinking:
                if group == nil { group = StepGroup(id: "g-\(e.id)", events: []) }
                group!.events.append(e)
            // A file the agent handed over is a thing you came back for, not a
            // step it took: it gets its own row rather than folding into a
            // "3 steps" group you would have to open to find it again.
            case .assistant, .approval, .approvalEnd, .notice, .file:
                closeGroup()
                current.items.append(.event(e))
            case let .turnEnd(_, _, cost, tokens):
                closeGroup()
                current.cost = cost
                current.tokens = tokens
                current.endedAt = e.ts
            case .session, .unknown:
                break
            }
        }
        closeTurn()
        return turns
    }
}


extension WireEvent {
    /// The id of a tool call or edit, for pairing it with its result.
    var toolIdIfCall: String? {
        switch data {
        case .tool(let id, _, _, _), .diff(let id, _, _): id
        default: nil
        }
    }
    var isThinking: Bool { if case .thinking = data { return true }; return false }
}
