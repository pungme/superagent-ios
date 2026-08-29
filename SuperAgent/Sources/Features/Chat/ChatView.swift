import PhotosUI
import SwiftUI

/// One conversation, rendered the way the desktop renders it: user bubbles in
/// the accent colour, assistant replies as Markdown, consecutive tool steps
/// collapsed into one row, approvals as cards, a footer per turn.
struct ChatView: View {
    let connection: Connection
    let chat: WireChat
    let workspace: WireWorkspace
    @Environment(AppState.self) private var app

    @State private var draft = ""
    @State private var error: String?
    @State private var attachments: [Attachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var dictation = Dictation()
    @State private var atBottom = true
    @State private var now = Date()
    @FocusState private var composerFocused: Bool

    private var transcript: Transcript { connection.transcripts[chat.id] ?? Transcript() }
    private var turns: [Turn] { TurnBuilder.build(transcript.events) }
    private var isWorking: Bool {
        if !transcript.streaming.isEmpty { return true }
        if transcript.outbox.contains(where: { $0.status == .sending }) { return true }
        guard let last = transcript.events.last else { return false }
        switch last.data {
        case .turnEnd, .notice: return false
        case .approvalEnd: return workspace.status == .working
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned, not scrolled away: you need to know the Mac is gone while
            // you're reading the latest reply, which is where you usually are.
            if connection.state != .connected {
                ConnectionBanner(connection: connection)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.card)
                    .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if transcript.events.isEmpty, transcript.streaming.isEmpty {
                            emptyState
                        }
                        ForEach(turns) { turn in
                            TurnView(turn: turn, pendingApprovals: pendingApprovals,
                                     answer: answer, choose: { send(text: $0) })
                        }
                        ForEach(transcript.outbox) { msg in
                            OutgoingRow(message: msg,
                                        retry: { connection.retry(chatId: chat.id, id: msg.id) },
                                        discard: { connection.discard(chatId: chat.id, id: msg.id) })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if !transcript.streaming.isEmpty {
                            AssistantBubble(text: transcript.streaming, streaming: true).id("streaming")
                        } else if isWorking {
                            WorkingRow(since: lastUserAt, now: now).id("working")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Theme.content)
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .bottomTrailing) {
                    if !atBottom {
                        Button { scrollToBottom(proxy) } label: {
                            Image(systemName: "arrow.down").font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(Theme.card, in: Circle())
                                .overlay(Circle().stroke(Theme.border))
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        }
                        .padding(14)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .onChange(of: transcript.events.count) { _, _ in if atBottom { scrollToBottom(proxy) } }
                .onChange(of: transcript.outbox.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: transcript.streaming) { _, _ in if atBottom { scrollToBottom(proxy) } }
                .onAppear { scrollToBottom(proxy, animated: false) }
            }
            Divider().overlay(Theme.border)
            Composer(
                draft: $draft, attachments: $attachments, pickerItems: $pickerItems,
                dictation: dictation, connected: connection.state == .connected,
                working: isWorking, commands: connection.commands[chat.id] ?? [],
                model: Binding(get: { app.preferredModel }, set: { app.preferredModel = $0 }),
                mode: Binding(get: { app.preferredMode }, set: { app.preferredMode = $0 }),
                onSend: { send(text: draft) },
                onStop: { Task { try? await connection.interrupt(chatId: chat.id) } })
        }
        .background(Theme.content)
        .navigationTitle(chat.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(chat.title ?? "Conversation").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(workspace.isBrowser ? (workspace.host ?? workspace.name) : workspace.name)
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onAppear { connection.subscribe(chatId: chat.id) }
        .onChange(of: connection.state) { _, s in if s == .connected { connection.subscribe(chatId: chat.id) } }
        .animation(.easeInOut(duration: 0.2), value: connection.state == .connected)
        .onChange(of: pickerItems) { _, items in loadPicked(items) }
        .onChange(of: dictation.transcript) { _, t in if !t.isEmpty { draft = t } }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
        .alert("Couldn't send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(Theme.textTertiary)
            Text("Message Claude about \(workspace.name)")
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textSecondary)
            Text("It runs on your Mac; you'll see every step here.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    private var lastUserAt: Date {
        if let m = transcript.outbox.last { return Date(timeIntervalSince1970: m.ts / 1000) }
        for e in transcript.events.reversed() { if case .user = e.data { return Date(timeIntervalSince1970: e.ts / 1000) } }
        return now
    }

    private func send(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        let perImage = Attachment.messageBudget / max(1, attachments.count)
        let images = attachments.map { (mediaType: "image/jpeg", data: $0.jpeg(maxBytes: perImage)) }
        withAnimation(.easeOut(duration: 0.2)) {
            draft = ""
            attachments = []
            connection.sendMessage(chatId: chat.id, text: text, images: images,
                                   model: app.preferredModel.isEmpty ? nil : app.preferredModel,
                                   mode: app.preferredMode)
        }
        Haptics.tap()
    }

    private func answer(id: String, approve: Bool) {
        Task {
            do { try await connection.answerApproval(id: id, approve: approve); Haptics.success() }
            catch { self.error = error.localizedDescription }
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let a = Attachment(imageData: data) {
                    attachments.append(a)
                }
            }
            pickerItems = []
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
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
}

/// A picked photo, downscaled the way the desktop pastes them.
struct Attachment: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    private let image: UIImage

    init?(imageData: Data) {
        guard let img = UIImage(data: imageData) else { return nil }
        image = Attachment.resized(img, maxSide: 1600)
        thumbnail = Attachment.resized(img, maxSide: 320)
    }

    /// JPEG bytes no larger than `maxBytes`. One relay frame carries the whole
    /// message (base64 inside base64 inside JSON), and the relay's ceiling is
    /// 1 MiB — Cloudflare's WebSocket message limit — so photos must be trimmed
    /// here, not there. Quality first, then size.
    func jpeg(maxBytes: Int) -> Data {
        var img = image
        var quality: CGFloat = 0.82
        var data = img.jpegData(compressionQuality: quality) ?? Data()
        while data.count > maxBytes {
            if quality > 0.5 {
                quality -= 0.12
            } else {
                img = Attachment.resized(img, maxSide: max(img.size.width, img.size.height) * 0.75)
                quality = 0.7
            }
            data = img.jpegData(compressionQuality: quality) ?? Data()
            if max(img.size.width, img.size.height) < 200 { break }
        }
        return data
    }

    /// Total JPEG budget for one message, split across its images.
    static let messageBudget = 480_000

    private static func resized(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        guard scale < 1 else { return img }
        let size = CGSize(width: (img.size.width * scale).rounded(), height: (img.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

struct WorkingRow: View {
    let since: Date
    let now: Date
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(Theme.textSecondary)
            Text("Working · \(Int(max(0, now.timeIntervalSince(since))))s")
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}
