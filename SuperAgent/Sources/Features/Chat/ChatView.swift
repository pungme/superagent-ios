import PhotosUI
import SwiftUI
import UIKit

/// One conversation, rendered the way the desktop renders it: user bubbles in
/// the accent colour, assistant replies as Markdown, consecutive tool steps
/// collapsed into one row, approvals as cards, a footer per turn.
struct ChatView: View {
    /// How this chat pushes a screen of its own. RootView owns the path; the
    /// agent's `open_file` is the only thing that needs it so far.
    var push: ((FileRef) -> Void)?
    /// The round icon buttons hold a glyph that grows with the text size;
    /// the well has to grow with it or the glyph spills over the circle.
    @ScaledMetric(relativeTo: .subheadline) private var well: CGFloat = 34

    let connection: Connection
    let chat: WireChat
    let workspace: WireWorkspace
    @Environment(AppState.self) private var app

    @State private var draft = ""
    @State private var error: String?
    @State private var attachments: [Attachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var dictation = Dictation()
    /// Whether the transcript is showing its end, read from the scroll
    /// geometry rather than from a sentinel view appearing and disappearing.
    @State private var atBottom = true
    /// Whether arriving rows should keep the view at the end. Deliberately not
    /// `atBottom`: that one goes false for a frame every time a batch lands,
    /// because the content grows before the anchor has moved the offset, and
    /// following it would strand a cold open halfway up the transcript — the
    /// bug this exists to stop. Only the reader's own scrolling changes it.
    @State private var following = true
    @State private var position = ScrollPosition()
    /// Everything in the chat that is neither the docked page nor the
    /// transcript: the project bar, the drag handle, the offline banner, the
    /// composer. Measured rather than assumed, because the banner comes and
    /// goes and the composer grows with the draft.
    @State private var chromeHeight: CGFloat = 200
    /// Set once the divider has been dragged. The cap that keeps the
    /// conversation readable is a default, not a rule: if you deliberately
    /// pull the page bigger, it goes bigger.
    @State private var pageResized = false
    @State private var showBrowserSheet = false
    @State private var showTasks = false
    /// The docked page above the chat. Defaults to shown when the Mac has one
    /// open; hidden again is remembered per conversation.
    /// Hidden by hand, remembered per conversation. It used to be plain view
    /// state, so it came back the moment the Mac pushed the next browser frame
    /// — and with it the polling, and a pane parked back in the Mac's window.
    /// Hiding a page should stay hidden and cost nothing until you ask for it.
    @State private var pageHidden = false
    /// Hidden by hand for this conversation, like the page above it.
    @State private var simHidden = false
    @State private var pageFraction: CGFloat = 0.42
    @State private var dragStart: CGFloat?
    @State private var containerHeight: CGFloat = 600
    @State private var showBranches = false
    @State private var creating = false
    @FocusState private var composerFocused: Bool

    private var transcript: Transcript { connection.transcripts[chat.id] ?? Transcript() }
    /// Rebuilt when the transcript actually changes — not on every layout pass.
    /// SwiftUI evaluates `body` constantly (a keystroke, a streamed word, a
    /// scroll); regrouping every event each time froze long conversations.
    @State private var turns: [Turn] = []
    @State private var tasks: [TaskItem] = []
    @State private var pendingApprovals: Set<String> = []
    /// Working while the Mac says this chat's agent process is alive (`live`,
    /// pushed on start/exit), or while text is streaming / a send is in flight.
    /// The last event alone was wrong: a turn that ended without a turn_end
    /// (interrupted, crashed) kept the spinner on for good.
    private var isWorking: Bool {
        if !transcript.streaming.isEmpty { return true }
        if transcript.outbox.contains(where: { $0.status == .sending }) { return true }
        return connection.chats.first { $0.id == chat.id }?.live ?? false
    }

    var body: some View {
        events(sheets(chrome))
    }

    /// `body` split into stages on purpose. As one chained expression, with the
    /// composer's focus binding threaded through it, the type checker gave up.
    private var chrome: some View {
        VStack(spacing: 0) {
            ProjectBar(connection: connection, workspace: workspace, pageOpen: pageShown,
                       pageAttached: pageAttached,
                       onBrowser: togglePage, onBranches: { showBranches = true }, onNewChat: newChat, creating: creating)
            // What the Mac has open sits above the conversation, as it sits
            // beside it on the desktop. The keyboard takes the room instead.
            // Attached but not on screen: say so, and offer it back. Without
            // this the page simply vanishes when you hide it or start typing,
            // and nothing says the conversation still has one.
            if simAttached, !simShown, !pageShown {
                Button {
                    simHidden = false
                    composerFocused = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone").superFont(12)
                        Text(simLabel).superFont(13).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Show").superFont(13, weight: .medium)
                        Image(systemName: "chevron.down").superFont(11, weight: .semibold)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .tint(Theme.textSecondary)
                .background(Theme.panel)
                .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if pageAttached, !pageShown {
                Button {
                    setPageHidden(false)
                    composerFocused = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe").superFont(12)
                        Text(pageLabel).superFont(13).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Show").superFont(13, weight: .medium)
                        Image(systemName: "chevron.down").superFont(11, weight: .semibold)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .tint(Theme.textSecondary)
                .background(Theme.panel)
                .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if simShown {
                SimulatorMirror(connection: connection, chat: chat,
                                onAttach: { data in if let a = Attachment(imageData: data) { attachments.append(a) } },
                                onHide: { withAnimation(.easeOut(duration: 0.2)) { simHidden = true } },
                                paused: composerFocused)
                    .frame(height: pageHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Rectangle().fill(Theme.border).frame(height: 1)
                    .overlay { Capsule().fill(Theme.textTertiary.opacity(0.5)).frame(width: 36, height: 4) }
                    .frame(height: 18).contentShape(Rectangle())
                    .background(Theme.panel)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let start = dragStart ?? pageFraction
                                dragStart = start
                                pageResized = true
                                pageFraction = min(0.72, max(0.2, start + v.translation.height / max(1, containerHeight)))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
            if pageShown {
                BrowserMirror(connection: connection, chat: chat, compact: true,
                              onAttach: { data in if let a = Attachment(imageData: data) { attachments.append(a) } },
                              onHide: { withAnimation(.easeOut(duration: 0.2)) { setPageHidden(true) } },
                              onExpand: { showBrowserSheet = true },
                              paused: composerFocused)
                    .frame(height: pageHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                // Drag the divider to give the page more or less room.
                Rectangle().fill(Theme.border).frame(height: 1)
                    .overlay {
                        Capsule().fill(Theme.textTertiary.opacity(0.5)).frame(width: 36, height: 4)
                    }
                    .frame(height: 18).contentShape(Rectangle())
                    .background(Theme.panel)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let start = dragStart ?? pageFraction
                                dragStart = start
                                pageResized = true
                                pageFraction = min(0.72, max(0.2, start + v.translation.height / max(1, containerHeight)))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
            // Pinned, not scrolled away: you need to know the Mac is gone while
            // you're reading the latest reply, which is where you usually are.
            if connection.state != .connected {
                ConnectionBanner(connection: connection)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.card)
                    .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            transcript(proxyless: true)
            Divider().overlay(Theme.border)
            composer
        }
            .background(Theme.content)
            // The docked page is a fraction of the screen; reading that height in the
            // background keeps a GeometryReader out of the layout path (it made every
            // pass re-measure the whole conversation).
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in containerHeight = h }
                }
            }
            .navigationTitle(chat.title ?? "Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { chatToolbar }
    }

    private func sheets(_ view: some View) -> some View {
        view
            .sheet(isPresented: $showBranches) { BranchSheet(connection: connection, workspace: workspace) }
            .sheet(isPresented: $showBrowserSheet) {
                BrowserSheet(connection: connection, chat: chat) { data in
                    if let a = Attachment(imageData: data) { attachments.append(a) }
                }
            }
            .sheet(isPresented: $showTasks) { TasksView(tasks: tasks) }
    }

    private func events(_ view: some View) -> some View {
        view
            .onAppear { connection.subscribe(chatId: chat.id); rebuild(); loadPageHidden(); markRead() }
            // Being in a conversation is reading it, so the mark keeps pace
            // with what arrives rather than stopping where you came in.
            .onChange(of: connection.chats.first(where: { $0.id == chat.id })?.updatedAt) { _, _ in markRead() }
            .onChange(of: transcript.lastSeq) { _, _ in rebuild() }
            .onChange(of: transcript.events.count) { _, _ in rebuild() }
            .onChange(of: connection.state) { _, s in if s == .connected { connection.subscribe(chatId: chat.id) } }
            .animation(.easeInOut(duration: 0.2), value: connection.state == .connected)
            .onChange(of: pickerItems) { _, items in loadPicked(items) }
            .onChange(of: dictation.transcript) { _, t in if !t.isEmpty { draft = t } }
            // The agent called `open_file`. Show it, as the Mac just did — but
            // only while this chat is the one on screen, so a file asked for by
            // a conversation you have left does not open over the one you moved
            // to. The transcript still says it was opened either way.
            .onChange(of: connection.openFileRequest) { _, req in openIfOurs(req) }
            .alert("Couldn't send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
    }

    /// The agent called `open_file`. Show it, as the Mac just did — but only
    /// while this chat is the one on screen, so a file asked for by a
    /// conversation you have left does not open over the one you moved to. The
    /// transcript keeps its card either way.
    private func openIfOurs(_ req: OpenFileRequest?) {
        guard let req, req.chatId == nil || req.chatId == chat.id else { return }
        connection.openFileRequest = nil
        push?(FileRef(workspaceId: req.workspaceId, path: req.path, chatId: chat.id))
    }

    /// Extracted from `body`: with the composer's focus binding threaded
    /// through, the whole view was one expression too large for the type
    /// checker to finish.
    @ViewBuilder
    private func transcript(proxyless _: Bool = true) -> some View {
        ScrollView {
            // Not lazy, deliberately. A LazyVStack only measures rows as it
            // realises them, so its height is an estimate, and every way of
            // asking for the end lands against that estimate: with a
            // tool-heavy transcript, where a collapsed step group is one line
            // and the reply under it is forty, the estimate is wrong by
            // thousands of points and the view settles on a stretch with
            // nothing realised in it. That is the blank chat. The Mac caps
            // what it sends at 400 events, so measuring them all is affordable.
            VStack(alignment: .leading, spacing: 12) {
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
                tail
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        // The scroll view keeps itself at the newest message. Nothing here
        // scrolls by hand, which is the whole point: driving the offset with
        // a ScrollViewReader while the keyboard, the composer's height and a
        // batch of arriving rows were all resizing the content meant the
        // offset was computed for a layout that no longer existed, and a
        // LazyVStack had nothing realised there, so the transcript landed on
        // a blank stretch.
        //
        // initialOffset opens on the end, so a cold open lands on the newest
        // message even though the transcript arrives after the view does.
        // sizeChanges keeps it there while rows stream in and while the
        // keyboard opens, and is nil once the reader has scrolled up, so
        // arriving messages never yank them back down.
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        // What the transcript actually got. Everything that is neither it nor
        // the docked page is the chrome, and knowing it is what lets the page
        // cap itself without hard-coding the height of a banner or a composer.
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, box in
            // Never while the divider is being dragged. The page's height is
            // derived from this measurement, and this measurement is taken from
            // the height the page leaves behind, so measuring mid-drag has the
            // two chasing each other every frame: that was the jank. A drag
            // reads the last settled value and the measurement resumes on
            // release. The threshold is generous for the same reason; chrome
            // only really changes when the banner appears or the composer grows
            // a line, and neither needs to be caught to the point.
            guard box > 0, pageShown, dragStart == nil else { return }
            let measured = containerHeight - pageHeight - box
            if measured > 0, abs(measured - chromeHeight) > 8 { chromeHeight = measured }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 40
        } action: { _, isAtEnd in
            if atBottom != isAtEnd { atBottom = isAtEnd }
        }
        .background(Theme.content)
        .scrollDismissesKeyboard(.interactively)
        // Tap the transcript to put the keyboard away, the way Messages
        // does. Simultaneous, so a tap that lands on an approval button or
        // a choice still reaches it.
        .simultaneousGesture(
            TapGesture().onEnded { if composerFocused { composerFocused = false } }
        )
        .overlay(alignment: .bottomTrailing) {
            if !atBottom {
                Button { following = true; scrollToEnd() } label: {
                    Image(systemName: "arrow.down").superFont(13, weight: .semibold)
                        .frame(width: well, height: well)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().stroke(Theme.border))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                }
                .padding(14)
                .transition(.scale.combined(with: .opacity))
            }
        }
        // Your own message always brings you back to the end, wherever you
        // were reading.
        .onChange(of: transcript.outbox.count) { _, _ in following = true; scrollToEnd() }
        // A reply streams in without adding an event, so it grows the tail
        // without going through rebuild(). Follow it too.
        .onChange(of: transcript.streaming) { _, _ in if following { scrollToEnd(animated: false) } }
        // Only the reader's own scrolling decides whether we keep following:
        // a scroll phase is a gesture, where `atBottom` is just geometry and
        // says false whenever a batch of rows outruns the anchor.
        .onScrollPhaseChange { _, phase in
            if phase == .idle { following = atBottom }
        }
    }

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(chat.title ?? "Conversation").superFont(15, weight: .semibold).lineLimit(1)
                    Text(workspace.isBrowser ? (workspace.host ?? workspace.name) : workspace.name)
                        .superFont(11).foregroundStyle(Theme.textSecondary)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !tasks.isEmpty {
                    Button { showTasks = true } label: {
                        Image(systemName: "checklist")
                            .overlay(alignment: .topTrailing) {
                                let open = tasks.filter { !$0.isDone }.count
                                if open > 0 {
                                    Text("\(open)").superFont(9, weight: .bold).foregroundStyle(Theme.accentFg)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Theme.accent, in: Capsule()).offset(x: 8, y: -6)
                                }
                            }
                    }
                    .accessibilityLabel("Tasks")
                }
            }
    }

    private var modelBinding: Binding<String> {
        Binding(get: { app.preferredModel }, set: { app.preferredModel = $0 })
    }

    private var modeBinding: Binding<String> {
        Binding(get: { app.preferredMode }, set: { app.preferredMode = $0 })
    }

    private var composer: some View {
        Composer(
            draft: $draft, attachments: $attachments, pickerItems: $pickerItems,
            dictation: dictation, connected: connection.state == .connected,
            working: isWorking, commands: connection.commands[chat.id] ?? [],
            model: modelBinding, mode: modeBinding,
            onSend: { send(text: draft) },
            onStop: { Task { try? await connection.interrupt(chatId: chat.id) } },
            focused: $composerFocused)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").superFont(28).foregroundStyle(Theme.textTertiary)
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
        return .now
    }

    /// What sits under the last turn: the text streaming in, or the working row.
    @ViewBuilder
    private var tail: some View {
        if !transcript.streaming.isEmpty {
            AssistantBubble(text: transcript.streaming, streaming: true).id("streaming")
        } else if isWorking {
            WorkingRow(since: lastUserAt).id("working")
        }
    }

    /// One pass over the events for everything derived from them.
    private func rebuild() {
        let events = transcript.events
        turns = TurnBuilder.build(events)
        tasks = TaskList.build(events)
        var open = Set<String>()
        for e in events {
            switch e.data {
            case .approval(let id, _, _, _, _): open.insert(id)
            case .approvalEnd(let id, _, _): open.remove(id)
            default: break
            }
        }
        pendingApprovals = open
        // The transcript arrives after this view does and lands in batches, and
        // the rows are wildly uneven — a collapsed step group is one line, the
        // reply under it is forty. A bottom anchor on its own settles against
        // whichever content size happened to be measured mid-arrival, which is
        // how opening a conversation drops you into the middle of it. Say where
        // to go on every batch instead of hoping the anchor knows.
        if following { scrollToEnd(animated: false) }
    }

    /// Read up to whatever has landed. The chat this view was handed is a
    /// snapshot from the list; the live row carries the newer timestamp.
    private func markRead() {
        if let c = connection.chats.first(where: { $0.id == chat.id }) { connection.unread.markSeen(c) }
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

    /// The Mac has a page open here, and you haven't put it away.
    /// The docked page's height, capped so the conversation keeps a usable
    /// amount of room. At 42% of a 724pt chat area the page took 304pt and the
    /// transcript was left with 219: less than one bubble, which reads as an
    /// empty chat you have to scroll up to find. The page can still be dragged
    /// bigger deliberately; it just will not start that way.
    private var pageAttached: Bool { connection.browsers[chat.id]?.open == true }

    private var simAttached: Bool { connection.simulators[chat.id]?.open == true }
    /// The simulator gets the docked slot only when there is no page in it: two
    /// mirrors over one conversation on a phone leaves room for neither.
    private var simShown: Bool { simAttached && !pageShown && !simHidden && !composerFocused }
    private var simLabel: String { connection.simulators[chat.id]?.device ?? "Simulator" }

    /// The page's host, or its title when there is no useful host.
    private var pageLabel: String {
        guard let b = connection.browsers[chat.id] else { return "Page" }
        if let host = URL(string: b.url)?.host?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
            return host
        }
        return b.title.isEmpty ? "Page" : b.title
    }

    private var pageHeight: CGFloat {
        let wanted = containerHeight * pageFraction
        let floor: CGFloat = pageResized ? 140 : 300
        let allowed = max(160, containerHeight - chromeHeight - floor)
        return max(160, min(wanted, allowed))
    }

    private static func hiddenKey(_ chatId: String) -> String { "pageHidden:" + chatId }

    private func loadPageHidden() {
        pageHidden = UserDefaults.standard.bool(forKey: Self.hiddenKey(chat.id))
    }

    private func setPageHidden(_ hidden: Bool) {
        pageHidden = hidden
        UserDefaults.standard.set(hidden, forKey: Self.hiddenKey(chat.id))
    }

    private var pageShown: Bool {
        connection.browsers[chat.id]?.open == true && !pageHidden && !composerFocused
    }

    /// The compass shows or hides the page; with nothing open it opens the
    /// full-screen mirror so you can type an address.
    private func togglePage() {
        if connection.browsers[chat.id]?.open == true {
            withAnimation(.easeOut(duration: 0.2)) { setPageHidden(!pageHidden) }
        } else {
            showBrowserSheet = true
        }
    }

    /// "New chat": a fresh conversation in this project, opened in place.
    private func newChat() {
        guard !creating else { return }
        creating = true
        Task {
            defer { creating = false }
            do {
                let id = try await connection.createChat(workspaceId: workspace.id)
                if let c = connection.chats.first(where: { $0.id == id }) { app.openChatId = c.id }
                Haptics.tap()
            } catch { self.error = error.localizedDescription }
        }
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

    private func scrollToEnd(animated: Bool = true) {
        if animated { withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .bottom) } }
        else { position.scrollTo(edge: .bottom) }
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
    var body: some View {
        // Ticks on its own: a timer on the whole chat re-evaluated every turn
        // in the conversation once a second.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.textSecondary)
                Text("Working · \(Int(max(0, context.date.timeIntervalSince(since))))s")
                    .superFont(12.5, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }
}

/// The bar above a project's chat, as on the desktop: Files, Todo (the board),
/// the project's name and branch, Preview for browser projects, New chat.
struct ProjectBar: View {
    let connection: Connection
    let workspace: WireWorkspace
    let pageOpen: Bool
    /// A page is attached to this conversation. When one is, the bar below says
    /// so and offers Show, so this bar does not need a button for it; the
    /// compass is only how you open a page when there is not one.
    var pageAttached = false
    let onBrowser: () -> Void
    let onBranches: () -> Void
    let onNewChat: () -> Void
    let creating: Bool

    var body: some View {
        HStack(spacing: 6) {
            // The chips scroll rather than truncate: at the larger text sizes
            // "Routines" and the branch name no longer fit across a phone, and
            // a bar that reads "Ro…" is worse than one you push sideways.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !workspace.isBrowser, !workspace.isComputer {
                        NavigationLink(value: WorkspacePanel(kind: .files, workspace: workspace)) { barButton("Files", "doc.text") }
                        NavigationLink(value: WorkspacePanel(kind: .board, workspace: workspace)) { barButton("Todo", "square.grid.2x2") }
                        NavigationLink(value: WorkspacePanel(kind: .routines, workspace: workspace)) { barButton("Routines", "clock.arrow.2.circlepath") }
                    }
                    if !pageAttached {
                        Button(action: onBrowser) { barButton(nil, pageOpen ? "safari.fill" : "safari", on: pageOpen) }
                            .buttonStyle(.plain).disabled(connection.state != .connected)
                            .accessibilityLabel(pageOpen ? "Hide the page" : "Show the page")
                    }
                    if let b = workspace.branch, !b.isEmpty {
                        Button(action: onBranches) { BranchChip(branch: b) }.buttonStyle(.plain)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // ✎ at the right, as on the desktop — outside the scroller, always reachable.
            Button(action: onNewChat) { barButton(nil, "square.and.pencil") }
                .buttonStyle(.plain).disabled(creating || connection.state != .connected)
                .accessibilityLabel("New chat")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }

    private func barButton(_ title: String?, _ icon: String, on: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).superFont(11, weight: .medium)
            if let title { Text(title).superFont(12, weight: .medium).lineLimit(1) }
        }
        .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
        .padding(.horizontal, title == nil ? 7 : 8).padding(.vertical, 5)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border))
    }
}

#if DEBUG
/// Debug-only: `-scrollHarness` opens a synthetic transcript so the scrolling
/// can be exercised in the simulator without pairing a Mac.
struct ChatHarness: View {
    @State private var connection: Connection?
    var body: some View {
        Group {
            if let c = connection {
                ChatView(connection: c,
                         chat: WireChat(id: "harness", workspaceId: "w", title: "Scroll harness",
                                        updatedAt: 0, live: false, preview: nil),
                         workspace: WireWorkspace(id: "w", name: "harness", path: "/tmp/harness",
                                                  kind: "repo", status: .idle, branch: "main",
                                                  browserUrl: nil, subrepos: nil))
            } else {
                ProgressView()
            }
        }
        .task { if connection == nil { connection = Connection.scrollHarness() } }
    }
}
#endif
