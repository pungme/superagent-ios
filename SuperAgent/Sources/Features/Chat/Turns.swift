import Foundation

/// The transcript, regrouped the way the desktop shows it: each user message
/// starts a turn; inside a turn, runs of tool activity collapse into one
/// "steps" row between the assistant's messages.
struct Turn: Identifiable, Equatable {
    let id: String
    var items: [TurnItem]
    var cost: Double?
    var tokens: Int?
    var startedAt: Double?
    var endedAt: Double?
    /// Roughly how much this turn has to lay out: the characters it says, and a
    /// little for each step. `utf8.count` is constant time on a native string.
    var weight: Int { items.reduce(0) { $0 + $1.weight } }

    var duration: TimeInterval? {
        guard let s = startedAt, let e = endedAt, e >= s else { return nil }
        return (e - s) / 1000
    }
}

enum TurnItem: Identifiable, Equatable {
    case event(WireEvent)
    case steps(StepGroup)

    /// A table cell is a view of its own with a few characters in it, and laid
    /// out nested inside stacks that measure it more than once: measured on a
    /// simulator a table costs several times a paragraph of the same length. A
    /// pipe is one cell edge, so it counts for extra.
    static func textWeight(_ text: String) -> Int {
        var pipes = 0
        for b in text.utf8 where b == UInt8(ascii: "|") { pipes += 1 }
        return text.utf8.count + 3 * pipes
    }

    /// Roughly how much this row has to lay out (see `Turn.weight`).
    var weight: Int {
        switch self {
        case .steps(let g): return 120 * min(g.events.count, 20)
        case .event(let e):
            switch e.data {
            case .user(_, let t, _, _, _), .assistant(_, let t), .thinking(_, let t), .notice(let t):
                return Self.textWeight(t)
            case .toolResult(_, _, let summary, _): return min(summary.utf8.count, 400)
            case .diff(_, _, let hunks):
                return min(hunks.reduce(0) { $0 + $1.added.count + $1.removed.count } * 80, 6_000)
            default: return 120
            }
        }
    }

    var id: String {
        switch self {
        case .event(let e): e.id
        case .steps(let g): g.id
        }
    }
}

/// Consecutive tool calls, edits, results and thoughts.
struct StepGroup: Identifiable, Equatable {
    let id: String
    var events: [WireEvent]

    var toolCount: Int { events.filter { if case .tool = $0.data { return true }; return false }.count }
    var editCount: Int { events.filter { if case .diff = $0.data { return true }; return false }.count }
    var failed: Int {
        events.filter { if case let .toolResult(_, ok, _, _) = $0.data { return !ok }; return false }.count
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
            case .toolResult(let toolId, _, _, _):
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
            case let .turnEnd(_, _, cost, tokens, _):
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


/// Which rows of a conversation are laid out.
///
/// The transcript is a non-lazy stack (see ChatView.transcript), so every row
/// in it is measured on every layout pass, and iOS makes several of those when
/// the app is put away (one per snapshot, in each appearance). The window is
/// cut by how much the rows SAY, newest first, and the cut can fall inside a
/// turn: a turn is everything the agent did for one message, and in a real
/// working session that is most of the conversation (110 000 characters in two
/// turns), so cutting only between turns cut nothing.
enum TurnWindow {
    struct Result {
        var turns: [Turn]
        /// Rows left out, for the "Show earlier" button.
        var hidden: Int
        /// The oldest row shown, nil when there is nothing.
        var firstItemId: String?
    }

    /// - maxTurns: never more turns than this are touched.
    /// - budget: stop once the rows taken weigh more than this...
    /// - leastItems: ...but always take at least this many, newest first.
    /// - floor: a row that stays shown even if the budget would cut it (what
    ///   the reader was looking at, see ChatView.windowFloor).
    static func visible(_ turns: [Turn], maxTurns: Int, budget: Int, leastItems: Int,
                        floor: String? = nil) -> Result {
        var used = 0
        var taken = 0
        var touched = 0
        var start: (turn: Int, item: Int)?
        outer: for ti in turns.indices.reversed() {
            if touched >= maxTurns { break }
            touched += 1
            let items = turns[ti].items
            for ii in items.indices.reversed() {
                if used > budget, taken >= leastItems { break outer }
                used += items[ii].weight
                taken += 1
                start = (ti, ii)
            }
        }
        // What the reader was looking at stays, wherever the budget would cut.
        if let floor, let s = start {
            search: for ti in turns.indices where ti <= s.turn {
                for ii in turns[ti].items.indices where turns[ti].items[ii].id == floor {
                    if ti < s.turn || ii < s.item { start = (ti, ii) }
                    break search
                }
            }
        }
        guard let start else { return Result(turns: [], hidden: turns.reduce(0) { $0 + $1.items.count }, firstItemId: nil) }
        var out = Array(turns[start.turn...])
        if start.item > 0 {
            out[0].items = Array(out[0].items[start.item...])
        }
        let hidden = turns[..<start.turn].reduce(0) { $0 + $1.items.count } + start.item
        return Result(turns: out, hidden: hidden, firstItemId: out.first?.items.first?.id)
    }
}
