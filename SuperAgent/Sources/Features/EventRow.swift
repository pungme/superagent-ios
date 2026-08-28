import SwiftUI

/// One row of the transcript, by event kind.
struct EventRow: View {
    let row: Row
    let pendingApproval: Bool
    let answer: (String, Bool) -> Void

    var body: some View {
        switch row.event.data {
        case let .user(_, text, images, from):
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)
                    if !images.isEmpty || from == .ios {
                        Text([images.isEmpty ? nil : "\(images.count) image\(images.count == 1 ? "" : "s")", from == .ios ? "from this phone" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        case let .assistant(_, text):
            AssistantBubble(text: text, streaming: false)
        case let .thinking(_, text):
            DisclosureGroup {
                Text(text).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            } label: {
                Label("Thought", systemImage: "brain").font(.caption).foregroundStyle(.tertiary)
            }
            .tint(.secondary)
        case let .tool(_, name, detail):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: row.result?.ok == false ? "xmark.circle" : "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(row.result?.ok == false ? .red : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if !detail.isEmpty {
                        Text(detail).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    if let r = row.result, !r.ok, !r.summary.isEmpty {
                        Text(r.summary).font(.caption2.monospaced()).foregroundStyle(.red.opacity(0.8)).lineLimit(3)
                    }
                }
            }
            .padding(.vertical, 2)
        case let .diff(_, file, hunks):
            let added = hunks.reduce(0) { $0 + $1.added.count }
            let removed = hunks.reduce(0) { $0 + $1.removed.count }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunks.enumerated()), id: \.offset) { _, h in
                        ForEach(h.removed, id: \.self) { l in DiffLine(text: l, sign: "-") }
                        ForEach(h.added, id: \.self) { l in DiffLine(text: l, sign: "+") }
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary).frame(width: 16)
                    Text(file).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("+\(added)").font(.caption2.monospaced()).foregroundStyle(.green)
                    Text("−\(removed)").font(.caption2.monospaced()).foregroundStyle(.red)
                }
            }
            .tint(.secondary)
        case let .notice(text):
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        case let .approval(id, toolName, preview, _, _):
            ApprovalCard(id: id, toolName: toolName, preview: preview, pending: pendingApproval, answer: answer)
        case let .approvalEnd(_, outcome, by):
            Text("\(outcome == .approved ? "Approved" : outcome == .denied ? "Denied" : "Expired") · \(by == .ios ? "from this phone" : "on the Mac")")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .toolResult, .turnEnd, .session, .unknown:
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
                MarkdownText(text)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottomTrailing) {
                if streaming {
                    Circle().fill(.secondary).frame(width: 6, height: 6).padding(8)
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 32)
        }
    }
}

/// Markdown where it parses, plain text where it doesn't. Fenced code keeps its line breaks.
struct MarkdownText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed).textSelection(.enabled)
        } else {
            Text(text).textSelection(.enabled)
        }
    }
}

struct DiffLine: View {
    let text: String
    let sign: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(sign).foregroundStyle(sign == "+" ? .green : .red)
            Text(text.isEmpty ? " " : text)
        }
        .font(.caption2.monospaced())
        .padding(.horizontal, 6).padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((sign == "+" ? Color.green : Color.red).opacity(0.08))
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
                .font(.subheadline.weight(.semibold))
            Text(preview)
                .font(.caption.monospaced())
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            if pending {
                HStack {
                    Button(role: .destructive) { answer(id, false) } label: {
                        Text("Deny").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { answer(id, true) } label: {
                        Text("Approve").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(pending ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(pending ? 0.5 : 0.15)))
    }

    private var verb: String {
        switch toolName {
        case "Bash": "run a command"
        case "Write": "write a file"
        case "Edit", "MultiEdit", "NotebookEdit": "edit a file"
        default: "use \(toolName)"
        }
    }
}
