import SwiftUI

/// One turn: the user's message, the collapsed steps, the reply, a quiet footer.
struct TurnView: View {
    let turn: Turn
    let pendingApprovals: Set<String>
    let answer: (String, Bool) -> Void
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(turn.items) { item in
                switch item {
                case .event(let e):
                    EventRow(event: e, pending: pendingApprovals.contains(approvalId(e) ?? ""), answer: answer, choose: choose)
                case .steps(let g):
                    StepGroupRow(group: g)
                }
            }
        }
    }

    private func approvalId(_ e: WireEvent) -> String? {
        if case .approval(let id, _, _, _, _) = e.data { return id }
        return nil
    }
}

struct StepGroupRow: View {
    let group: StepGroup
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                    Text(headline).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    if !group.summary.isEmpty {
                        Text("· " + group.summary).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    if group.failed > 0 {
                        Text("· \(group.failed) failed").font(.system(size: 13)).foregroundStyle(Theme.danger)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group.events) { e in StepRow(event: e, result: result(for: e)) }
                }
                .padding(.leading, 16)
            }
        }
    }

    private var headline: String {
        let n = group.toolCount + group.editCount
        var parts = ["\(n) step\(n == 1 ? "" : "s")"]
        if group.editCount > 0 { parts.append("\(group.editCount) edit\(group.editCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func result(for e: WireEvent) -> (ok: Bool, summary: String)? {
        let id: String
        switch e.data {
        case .tool(let i, _, _, _): id = i
        case .diff(let i, _, _): id = i
        default: return nil
        }
        for r in group.events { if case let .toolResult(toolId, ok, summary) = r.data, toolId == id { return (ok, summary) } }
        return nil
    }
}

/// One tool call / edit / thought inside an expanded step group.
struct StepRow: View {
    let event: WireEvent
    let result: (ok: Bool, summary: String)?

    var body: some View {
        switch event.data {
        case let .tool(_, name, detail, _):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result?.ok == false ? "xmark.circle" : icon(for: name))
                    .font(.system(size: 11)).foregroundStyle(result?.ok == false ? Theme.danger : Theme.textTertiary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(StepGroup.verb(for: name)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Text(prettyName(name)).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                    }
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    if let r = result, !r.ok, !r.summary.isEmpty {
                        Text(r.summary).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.danger.opacity(0.85)).lineLimit(3)
                    }
                }
            }
        case let .diff(_, file, hunks):
            DiffCard(file: file, hunks: hunks)
        case let .thinking(_, text):
            DisclosureGroup {
                Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            } label: {
                Label("Thought", systemImage: "sparkle").font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
            }
            .tint(Theme.textTertiary)
        case .toolResult:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private func icon(for tool: String) -> String {
        switch StepGroup.verb(for: tool) {
        case "Running": "terminal"
        case "Reading": "doc.text.magnifyingglass"
        case "Editing": "pencil"
        case "Browsing": "globe"
        case "Delegating": "person.2"
        case "Planning": "checklist"
        default: "wrench.and.screwdriver"
        }
    }
    private func prettyName(_ tool: String) -> String {
        tool.replacingOccurrences(of: "mcp__cove-browser__", with: "")
    }
}

struct DiffCard: View {
    let file: String
    let hunks: [DiffHunk]
    @State private var open = false
    var body: some View {
        let added = hunks.reduce(0) { $0 + $1.added.count }
        let removed = hunks.reduce(0) { $0 + $1.removed.count }
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).frame(width: 14)
                    Text(file).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Text("+\(added)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.added)
                    Text("−\(removed)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.removed)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(hunks.enumerated()), id: \.offset) { hi, h in
                            ForEach(Array(h.removed.enumerated()), id: \.offset) { _, l in DiffLine(text: l, sign: "-") }
                            ForEach(Array(h.added.enumerated()), id: \.offset) { _, l in DiffLine(text: l, sign: "+") }
                            if hi < hunks.count - 1 { Divider().padding(.vertical, 2) }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

struct DiffLine: View {
    let text: String
    let sign: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(sign).foregroundStyle(sign == "+" ? Theme.added : Theme.removed)
            Text(text.isEmpty ? " " : text)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.horizontal, 6).padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((sign == "+" ? Theme.added : Theme.removed).opacity(0.09))
    }
}

/// A message, notice or approval — the rows that are not steps.
struct EventRow: View {
    let event: WireEvent
    let pending: Bool
    let answer: (String, Bool) -> Void
    let choose: (String) -> Void

    var body: some View {
        switch event.data {
        case let .user(_, text, images, from):
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(text)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Theme.accentFg)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                        .textSelection(.enabled)
                    if !images.isEmpty || from == .ios {
                        Text([images.isEmpty ? nil : "\(images.count) image\(images.count == 1 ? "" : "s")", from == .ios ? "from this phone" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        case let .assistant(_, text):
            let (body, choices) = MarkdownParser.extractChoices(text)
            VStack(alignment: .leading, spacing: 8) {
                if !body.isEmpty { AssistantBubble(text: body, streaming: false) }
                if let choices { ChoicesView(choices: choices, choose: choose) }
            }
        case let .notice(text):
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        case let .approval(id, toolName, preview, _, _):
            ApprovalCard(id: id, toolName: toolName, preview: preview, pending: pending, answer: answer)
        case let .approvalEnd(_, outcome, by):
            Text("\(outcome == .approved ? "Approved" : outcome == .denied ? "Denied" : "Expired") · \(by == .ios ? "from this phone" : "on the Mac")")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        default:
            EmptyView()
        }
    }
}

struct AssistantBubble: View {
    let text: String
    let streaming: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownView(text: text)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.assistantBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if streaming { StreamingDot().padding(9) }
            }
            Spacer(minLength: 28)
        }
    }
}

struct StreamingDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Theme.textSecondary).frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// The desktop's ```ask block: a question with tappable options.
struct ChoicesView: View {
    let choices: MarkdownParser.Choices
    let choose: (String) -> Void
    @State private var picked: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !choices.question.isEmpty {
                Text(choices.question).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
            }
            ForEach(choices.options, id: \.label) { opt in
                Button {
                    Haptics.tap()
                    if choices.multiple {
                        if picked.contains(opt.label) { picked.remove(opt.label) } else { picked.insert(opt.label) }
                    } else { choose(opt.label) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            if let h = opt.hint, !h.isEmpty { Text(h).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
                        }
                        Spacer()
                        Image(systemName: choices.multiple ? (picked.contains(opt.label) ? "checkmark.circle.fill" : "circle") : "arrow.right")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderStrong))
                }
                .buttonStyle(.plain)
            }
            if choices.multiple {
                Button("Send \(picked.count) choice\(picked.count == 1 ? "" : "s")") { choose(picked.sorted().joined(separator: ", ")) }
                    .disabled(picked.isEmpty)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(Theme.textPrimary)
            }
        }
        .padding(.leading, 4)
    }
}

struct ApprovalCard: View {
    let id: String
    let toolName: String
    let preview: String
    let pending: Bool
    let answer: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pending ? "Claude wants to \(verb)" : "Asked to \(verb)", systemImage: "hand.raised")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(preview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if pending {
                HStack(spacing: 8) {
                    Button { answer(id, false) } label: { Text("Deny").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).tint(Theme.danger)
                    Button { answer(id, true) } label: { Text("Approve").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentFg)
                }
            }
        }
        .padding(12)
        .background(Theme.needsYou.opacity(pending ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.needsYou.opacity(pending ? 0.5 : 0.15)))
    }

    private var verb: String {
        switch toolName {
        case "Bash": "run a command"
        case "Write": "write a file"
        case "Edit", "MultiEdit", "NotebookEdit": "edit a file"
        default: "use \(toolName.replacingOccurrences(of: "mcp__cove-browser__", with: ""))"
        }
    }
}

/// A message we've sent that the Mac hasn't echoed yet: same bubble, with a
/// quiet status line under it instead of the origin.
struct OutgoingRow: View {
    let message: Outgoing
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Theme.accentFg)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                        .opacity(failed ? 0.55 : 1)
                }
                HStack(spacing: 8) {
                    if !message.images.isEmpty {
                        Text("\(message.images.count) image\(message.images.count == 1 ? "" : "s")")
                    }
                    switch message.status {
                    case .queued:
                        Label("Waiting for the Mac", systemImage: "clock")
                    case .sending:
                        Label("Sending", systemImage: "arrow.up.circle")
                    case .failed(let why):
                        Text("Not delivered · \(why)").lineLimit(1)
                        Button("Retry", action: retry).foregroundStyle(Theme.textPrimary)
                        Button("Discard", action: discard).foregroundStyle(Theme.textPrimary)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(failed ? Theme.danger : Theme.textTertiary)
            }
        }
    }

    private var failed: Bool { if case .failed = message.status { return true }; return false }
}
