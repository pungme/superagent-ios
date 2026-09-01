import Foundation
import SwiftUI

/// One turn: the user's message, the collapsed steps, the reply, a quiet footer.
struct TurnView: View {
    /// Only so a picture on a message this phone did not send can be fetched
    /// from the Mac; nothing else down here talks to it.
    let connection: Connection
    let turn: Turn
    let pendingApprovals: Set<String>
    let answer: (String, Bool) -> Void
    let choose: (String) -> Void
    /// Hold a message to answer that one specifically.
    let reply: (ReplyQuote) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(turn.items) { item in
                switch item {
                case .event(let e):
                    EventRow(connection: connection, event: e, pending: pendingApprovals.contains(approvalId(e) ?? ""), answer: answer, choose: choose, reply: reply)
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
                        .superFont(10, weight: .bold)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                    Text(headline).superFont(13, weight: .medium).foregroundStyle(Theme.textSecondary)
                    if !group.summary.isEmpty {
                        Text("· " + group.summary).superFont(13).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    if group.failed > 0 {
                        Text("· \(group.failed) failed").superFont(13).foregroundStyle(Theme.danger)
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
                    .superFont(11).foregroundStyle(result?.ok == false ? Theme.danger : Theme.textTertiary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(StepGroup.verb(for: name)).superFont(12.5, weight: .medium).foregroundStyle(Theme.textSecondary)
                        Text(prettyName(name)).superFont(11.5).foregroundStyle(Theme.textTertiary)
                    }
                    if !detail.isEmpty {
                        Text(detail).superFont(12, design: .monospaced).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    if let r = result, !r.ok, !r.summary.isEmpty {
                        Text(r.summary).superFont(11.5, design: .monospaced).foregroundStyle(Theme.danger.opacity(0.85)).lineLimit(3)
                    }
                }
            }
        case let .file(_, path, name, workspaceId, size, mediaType):
            FileHandoffCard(path: path, name: name, workspaceId: workspaceId,
                            chatId: event.chatId, size: size, mediaType: mediaType)
        case let .diff(_, file, hunks):
            DiffCard(file: file, hunks: hunks)
        case let .thinking(_, text):
            DisclosureGroup {
                Text(text).superFont(12.5).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            } label: {
                Label("Thought", systemImage: "sparkle").superFont(12.5).foregroundStyle(Theme.textTertiary)
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
                    Image(systemName: "doc.text").superFont(11).foregroundStyle(Theme.textTertiary).frame(width: 14)
                    Text(file).superFont(12.5, weight: .medium).foregroundStyle(Theme.textSecondary)
                    Text("+\(added)").superFont(11.5, design: .monospaced).foregroundStyle(Theme.added)
                    Text("−\(removed)").superFont(11.5, design: .monospaced).foregroundStyle(Theme.removed)
                    Spacer()
                    Image(systemName: "chevron.right").superFont(10, weight: .bold).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(Theme.textTertiary)
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
        .superFont(11.5, design: .monospaced)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((sign == "+" ? Theme.added : Theme.removed).opacity(0.09))
    }
}

/// A message, notice or approval — the rows that are not steps.
struct EventRow: View {
    let connection: Connection
    let event: WireEvent
    let pending: Bool
    let answer: (String, Bool) -> Void
    let choose: (String) -> Void
    let reply: (ReplyQuote) -> Void

    var body: some View {
        switch event.data {
        case let .user(_, text, images, from, replyTo):
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    // The quote sits above the message that answers it, the way
                    // every messaging app puts it.
                    if let replyTo { ReplyQuoteChip(quote: replyTo) }
                    // What you sent, above what you said about it — the order
                    // they were picked in, and the order the agent got them.
                    SentImagesRow(connection: connection, messageId: event.id, count: images.count)
                    if !text.isEmpty {
                        Text(text)
                            .superFont(15.5)
                            .foregroundStyle(Theme.accentFg)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                            .textSelection(.enabled)
                            .contextMenu {
                                Button { reply(ReplyQuote(role: .user, text: text)) } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }
                            }
                    }
                    if from == .ios {
                        Text("from this phone")
                            .superFont(11).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        case let .assistant(_, text):
            let (body, choices) = MarkdownParser.extractChoices(text)
            VStack(alignment: .leading, spacing: 8) {
                if !body.isEmpty {
                    AssistantBubble(text: body, streaming: false)
                        .contextMenu {
                            Button { reply(ReplyQuote(role: .assistant, text: body)) } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                        }
                }
                if let choices { ChoicesView(choices: choices, choose: choose) }
            }
        case let .file(_, path, name, workspaceId, size, mediaType):
            FileHandoffCard(path: path, name: name, workspaceId: workspaceId,
                            chatId: event.chatId, size: size, mediaType: mediaType)
        case let .notice(text):
            Text(text).superFont(12.5).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        case let .approval(id, toolName, preview, _, _):
            ApprovalCard(id: id, toolName: toolName, preview: preview, pending: pending, answer: answer)
        case let .approvalEnd(_, outcome, by):
            Text("\(outcome == .approved ? "Approved" : outcome == .denied ? "Denied" : "Expired") · \(by == .ios ? "from this phone" : "on the Mac")")
                .superFont(11).foregroundStyle(Theme.textTertiary)
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
                    .superFont(15.5)
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
                Text(choices.question).superFont(14, weight: .medium).foregroundStyle(Theme.textPrimary)
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
                            Text(opt.label).superFont(14, weight: .medium).foregroundStyle(Theme.textPrimary)
                            if let h = opt.hint, !h.isEmpty { Text(h).superFont(12).foregroundStyle(Theme.textSecondary) }
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
                    .superFont(13, weight: .semibold)
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
                .superFont(14, weight: .semibold).foregroundStyle(Theme.textPrimary)
            Text(preview)
                .superFont(12, design: .monospaced)
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
            VStack(alignment: .trailing, spacing: 6) {
                // The quote too, so a reply looks the same in flight as it will
                // once the Mac echoes it back.
                if let replyTo = message.replyTo { ReplyQuoteChip(quote: replyTo) }
                // In flight, the pictures are still in hand — no need to go to
                // disk for them, and no wait before they appear.
                if !message.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(message.images.enumerated()), id: \.offset) { _, im in
                            if let ui = UIImage(data: im.data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 132, height: 132)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Theme.border, lineWidth: 1)
                                    }
                                    .opacity(failed ? 0.55 : 1)
                            }
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .superFont(15.5)
                        .foregroundStyle(Theme.accentFg)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                        .opacity(failed ? 0.55 : 1)
                }
                HStack(spacing: 8) {
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
                .superFont(11)
                .foregroundStyle(failed ? Theme.danger : Theme.textTertiary)
            }
        }
    }

    private var failed: Bool { if case .failed = message.status { return true }; return false }
}


/// A file the agent handed over, kept in the conversation so you can come back
/// to it. Tapping opens the same viewer the Files tab uses; a file outside any
/// project has nowhere to fetch from, so it says where it is instead.
///
/// Written plainly on purpose. The first version used a switch expression with
/// an optional pattern and a `where` clause, which builds here and does not on
/// Xcode Cloud's older toolchain — where it failed as two invented errors on
/// unrelated lines further up this file. Nothing here needs to be clever.
/// The connection, floating over the end of the conversation.
///
/// It used to be a band across the top of the chat: the same words, in the one
/// place you are always looking. A status belongs where you can see it and not
/// where you are reading — so it sits above the composer, over the last
/// message, small enough to ignore and close enough to act on.
/// What you are about to answer, above the composer.
///
/// The same quote the sent message will carry, shown before it goes so you can
/// see what you picked and change your mind. Dismissing it here is the only way
/// out other than sending.
struct ReplyBar: View {
    let quote: ReplyQuote
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .superFont(12).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.role == .user ? "Replying to you" : "Replying to the agent")
                    .superFont(11, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                Text(quote.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                    .superFont(12.5)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .superFont(12, weight: .semibold)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}

/// The message a reply answers, drawn above it.
///
/// One line, clipped: it is a pointer back to something already on screen, not
/// a second copy of it. The bar down the leading edge is what makes it read as
/// a quote rather than as another message.
struct ReplyQuoteChip: View {
    let quote: ReplyQuote

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.role == .user ? "You" : "Agent")
                    .superFont(11, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                Text(quote.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                    .superFont(12.5)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 6)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ConnectionFloat: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 8) {
            if connection.state == .connecting {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(Theme.needsYou).frame(width: 7, height: 7)
            }
            Text(ConnectionPill.label(for: connection.state))
                .superFont(12.5, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
            if connection.state != .connecting {
                Button("Retry") { connection.connect() }
                    .superFont(12.5, weight: .semibold)
                    .tint(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay { Capsule().stroke(Theme.border, lineWidth: 1) }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
    }
}

/// The pictures a message was sent with.
///
/// The thumbnails are this phone's own (see SentImages) — the transcript event
/// carries only how many there were, because the bytes went to the agent rather
/// than into the log. When there is no thumbnail to show — a message sent from
/// the Mac, or one whose cache the system has reclaimed — it says how many
/// there were, which is what the whole row used to be.
struct SentImagesRow: View {
    let connection: Connection
    let messageId: String
    let count: Int
    @State private var shots: [UIImage] = []

    var body: some View {
        Group {
            if count > 0 {
                if shots.isEmpty {
                    Text("\(count) image\(count == 1 ? "" : "s")")
                        .superFont(11).foregroundStyle(Theme.textTertiary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 132, height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Theme.border, lineWidth: 1)
                                }
                        }
                    }
                    .accessibilityLabel("\(count) image\(count == 1 ? "" : "s") you sent")
                }
            }
        }
        .task(id: messageId) {
            guard count > 0, shots.isEmpty else { return }
            let found = SentImages.load(messageId: messageId, count: count)
            if !found.isEmpty { shots = found; return }
            // Nothing local: this message came from the Mac, or the cache was
            // reclaimed. The Mac keeps a thumbnail beside the log for exactly
            // this — ask for it rather than showing "1 image" as grey text.
            var fetched: [UIImage] = []
            for i in 0..<count {
                guard let wire = try? await connection.chatImage(messageId: messageId, index: i),
                      let data = Data(base64Encoded: wire.data),
                      let image = UIImage(data: data) else { continue }
                fetched.append(image)
            }
            if !fetched.isEmpty { shots = fetched }
        }
    }
}

struct FileHandoffCard: View {
    let path: String
    let name: String
    let workspaceId: String?
    let chatId: String
    let size: Int?
    let mediaType: String?

    private var subtitle: String {
        guard let size else { return path }
        return FileHandoffCard.humanSize(size) + " · " + path
    }

    /// Plain arithmetic rather than ByteCountFormatter: this file imports
    /// SwiftUI, and leaning on Foundation through it is exactly the kind of
    /// thing that resolves on one toolchain and not another. Build 32 and 33
    /// failed on Xcode Cloud with invented errors elsewhere in this file, which
    /// is what the compiler does when it cannot resolve something here.
    static func humanSize(_ bytes: Int) -> String {
        if bytes < 1000 { return "\(bytes) bytes" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        // -1 because the first division is what gets us to KB: starting at 0
        // called 1,700 bytes "1.7 MB".
        var unit = -1
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded = (value * 10).rounded() / 10
        let whole = rounded == rounded.rounded()
        let number = whole ? "\(Int(rounded))" : "\(rounded)"
        return number + " " + units[unit]
    }

    private var icon: String {
        let type = mediaType ?? ""
        if type.hasPrefix("image/") { return "photo" }
        if type == "application/pdf" { return "doc.richtext" }
        if type == "application/zip" { return "shippingbox" }
        if type == "text/csv" { return "tablecells" }
        return "doc"
    }

    private var card: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .superFont(16)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .superFont(13.5, weight: .medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .superFont(11.5)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if workspaceId != nil {
                Image(systemName: "chevron.right")
                    .superFont(11, weight: .semibold)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    @ViewBuilder
    var body: some View {
        if let workspaceId {
            NavigationLink(value: FileRef(workspaceId: workspaceId, path: path, chatId: chatId)) {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }
}
