import SwiftUI

/// One conversation: the event log rendered as rows, the streaming reply, and a composer.
struct ChatView: View {
    let connection: Connection
    let chat: WireChat
    let workspace: WireWorkspace

    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var composerFocused: Bool

    private var transcript: Transcript { connection.transcripts[chat.id] ?? Transcript() }
    private var isWorking: Bool { workspace.status == .working || !transcript.streaming.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if connection.state != .connected {
                            ConnectionBanner(connection: connection)
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        ForEach(rows) { row in
                            EventRow(row: row, pendingApproval: pendingApprovals.contains(row.approvalId ?? ""),
                                     answer: { id, approve in answer(id: id, approve: approve) })
                                .id(row.id)
                        }
                        if !transcript.streaming.isEmpty {
                            AssistantBubble(text: transcript.streaming, streaming: true).id("streaming")
                        } else if isWorking, transcript.events.last.map({ isTurnEnd($0) }) == false {
                            WorkingIndicator().id("working")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: transcript.events.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: transcript.streaming) { _, _ in scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy, animated: false) }
            }
            Divider()
            composer
        }
        .navigationTitle(chat.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { connection.subscribe(chatId: chat.id) }
        .onChange(of: connection.state) { _, s in if s == .connected { connection.subscribe(chatId: chat.id) } }
        .alert("Couldn't send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message the agent…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .focused($composerFocused)
                .onSubmit(send)
            if isWorking {
                Button { Task { try? await connection.interrupt(chatId: chat.id) } } label: {
                    Image(systemName: "stop.fill").font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("Stop")
            }
            Button(action: send) {
                Image(systemName: "arrow.up").font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending || connection.state != .connected)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        draft = ""
        Task {
            defer { sending = false }
            do { try await connection.sendMessage(chatId: chat.id, text: text) }
            catch {
                self.error = error.localizedDescription
                draft = text
            }
        }
    }

    private func answer(id: String, approve: Bool) {
        Task {
            do { try await connection.answerApproval(id: id, approve: approve) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func isTurnEnd(_ e: WireEvent) -> Bool {
        if case .turnEnd = e.data { return true }
        return false
    }

    /// Approvals still waiting: asked, not yet ended.
    private var pendingApprovals: Set<String> {
        var open = Set<String>()
        for e in transcript.events {
            switch e.data {
            case .approval(let id, _, _, _, _): open.insert(id)
            case .approvalEnd(let id, _, _): open.remove(id)
            default: break
            }
        }
        return open
    }

    /// Events worth a row. Tool results fold into their tool; session/turn_end are silent.
    private var rows: [Row] {
        var out: [Row] = []
        var resultsByTool: [String: (ok: Bool, summary: String)] = [:]
        for e in transcript.events {
            if case let .toolResult(toolId, ok, summary) = e.data { resultsByTool[toolId] = (ok, summary) }
        }
        for e in transcript.events {
            switch e.data {
            case .session, .turnEnd, .toolResult: continue
            case .tool(let id, _, _): out.append(Row(event: e, result: resultsByTool[id]))
            default: out.append(Row(event: e, result: nil))
            }
        }
        return out
    }
}

struct Row: Identifiable {
    let event: WireEvent
    let result: (ok: Bool, summary: String)?
    var id: String { event.id }
    var approvalId: String? {
        if case .approval(let id, _, _, _, _) = event.data { return id }
        return nil
    }
}

struct WorkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Working…").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
