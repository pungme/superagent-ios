import PhotosUI
import SwiftUI

/// The desktop composer, sized for a thumb: attachments above, the field with
/// a mic and a send button, and the Model / Mode pills underneath. Typing "/"
/// opens the commands the agent reported for this session.
struct Composer: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// In a split window the composer is the mini one (see `mini`): the
    /// pills fold into the agent's logo, as the Mac's composer does there.
    @Environment(\.compactComposer) private var compact
    /// The round icon buttons hold a glyph that grows with the text size;
    /// the well has to grow with it or the glyph spills over the circle. It
    /// stops growing at 46 pt, and the glyphs stop at .accessibility1, because
    /// past that the three wells eat the whole row and there is nowhere left to
    /// type — the message field and the transcript keep scaling without them.
    @ScaledMetric(relativeTo: .subheadline) private var wellMetric: CGFloat = 34
    private var well: CGFloat { min(wellMetric, 46) }

    /// The draft lives HERE, not in ChatView, and that is the whole point.
    /// When it lived on ChatView every keystroke re-evaluated the entire
    /// conversation — a non-lazy transcript of hundreds of turns re-diffed per
    /// character — so typing crawled in long chats. Owned by the composer, a
    /// keystroke invalidates only this small view; the transcript never sees it.
    @State private var draft: String = ""
    /// Which conversation's draft this is, for load/save and to reload when the
    /// composer is reused across a chat switch.
    let chatID: String
    @Binding var attachments: [Attachment]
    @Binding var pickerItems: [PhotosPickerItem]
    /// Files on their way to the agent — anything, not just pictures.
    @Binding var files: [PickedFile]
    /// What the Mac's composer holds for this chat, and how to tell the Mac
    /// what this one does. See `DraftSync`.
    var remoteDraft: Connection.RemoteDraft? = nil
    var pushDraft: (String) async -> Bool = { _ in false }
    @State private var draftPush: Task<Void, Never>?
    let dictation: Dictation
    let connected: Bool
    let working: Bool
    let commands: [String]
    /// Live context and the window it lives in, when a turn has reported one.
    let context: (used: Int, window: Int)?
    @Binding var model: String
    @Binding var mode: String
    /// Codex reports the models available to this account when its session
    /// starts. Claude uses the curated list below.
    let sessionModels: [WireModelOption]
    /// The exact model the session is running ("claude-opus-5-5[1m]"), as the
    /// Mac reported it — so the picker can say "Opus 5.5", not just "Opus".
    var runningModel: String? = nil
    /// Which agent this conversation runs on, and how to move it. Codex exposes
    /// its account default here; permission modes are shared by both agents.
    let provider: String
    let onProvider: (String) -> Void
    /// The Mac's browsers and the one this conversation uses; nil (or a
    /// single entry) when there is nothing to choose between.
    /// This agent's accounts and the one the chat is on, with their usage.
    var accounts: [WireAccount] = []
    var currentAccount: String? = nil
    var onAccount: (String) -> Void = { _ in }
    var browserChoices: BrowserChoices? = nil
    var onBrowser: (String) -> Void = { _ in }
    /// The composer clears itself and hands the text up; ChatView does the rest
    /// (attachments, reply quote, delivery) and never touches the draft.
    let onSend: (String) -> Void
    let onStop: () -> Void
    /// "Send when it's done": held on the Mac, not here — see `Connection.queueSend`.
    /// ChatView owns the RPC call and the resulting list; this view only shows it.
    let heldSends: [HeldSend]
    let onQueue: (String) -> Void
    let onCancelQueue: (String) -> Void

    /// Owned by ChatView. The chat needs to know when the keyboard is up: it
    /// gives the docked page's room back to the transcript, pauses the mirror,
    /// and lets a tap on the transcript put the keyboard away. A private
    /// @FocusState here left all three dead, since nothing outside could see it.
    var focused: FocusState<Bool>.Binding

    /// Fallback only: the Mac sends Claude's real line-up (from its CLI) on the
    /// session event. Families, not versions, so this never goes stale.
    static let models: [WireModelOption] = [
        .init(id: "", label: "Default", hint: "Recommended · best for everyday, complex tasks"),
        .init(id: "opus[1m]", label: "Opus", hint: "1M context · everyday, complex tasks"),
        .init(id: "fable", label: "Fable", hint: "Most capable, for the hardest, longest tasks"),
        .init(id: "sonnet", label: "Sonnet", hint: "Efficient for routine tasks"),
        .init(id: "haiku", label: "Haiku", hint: "Fastest for quick answers")
    ]
    static let modes: [(id: String, label: String, hint: String)] = [
        ("bypassPermissions", "Full", "Runs commands and edits, like your terminal"),
        ("ask", "Ask", "Asks before commands and edits — you approve here"),
        ("acceptEdits", "Edits", "Applies file edits; some commands may be refused"),
        ("plan", "Plan", "Read-only — plans without changing anything")
    ]

    /// The pills (agent, account, model, mode…) are folded into the agent's
    /// logo at the start of the field, as on the Mac's narrow composer: one
    /// clean line until they are wanted. Remembered, so it stays as left.
    @AppStorage("composer.settingsOpen") private var settingsOpen = false

    /// The composer's own width, to fold into the mini layout when a column
    /// is too narrow for the pills, as the Mac's does (its container query).
    /// Whether the column is narrower than `miniWidth`. A yes/no, not the width:
    /// keeping the width itself rebuilt the composer on every point of every
    /// layout pass, and on a phone (build 182) that ran into an 8 s hang that
    /// iOS killed the app for.
    @State private var narrow = false
    /// Narrower than this on an iPad (a Stage Manager window, a column beside
    /// a page) and the pills would wrap onto two lines. Below an 11-inch
    /// iPad's portrait chat column with the sidebar out (about 514 pt) and an
    /// iPad mini's (about 424 pt), so a full single chat keeps its layout.
    static let miniWidth: CGFloat = 400
    /// The mini composer: one row (+, the box with the agent's logo, send),
    /// every setting in the logo's menu. In a split window always; elsewhere
    /// on an iPad when the column is narrow. A phone keeps its own layout.
    private var mini: Bool {
        compact || (sizeClass == .regular && narrow)
    }

    /// The agent's logo in the box, with the usage limit as a ring round it.
    private func logoMark(highlighted: Bool) -> some View {
        ZStack {
            // How much of the account's usage limit is used, as a
            // ring round the logo; it reddens as it fills.
            if let ring = limitFraction {
                Circle().stroke(Theme.textTertiary.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: max(0.02, ring))
                    .stroke(memoryColour(ring), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            ProviderMark(provider: provider, size: 17)
        }
        .frame(width: well - 6, height: well - 6)
        .frame(width: well, height: well)
        .background(highlighted ? Theme.accentSoft : .clear, in: Circle())
        .contentShape(Circle())
    }

    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    /// Nothing the recogniser says after a send belongs in the emptied composer;
    /// a recogniser revises its final result after you stop it, and that
    /// revision used to type the sent message straight back in.
    @State private var dictationSpent = false

    /// The inline "send now / send when it finishes" menu, opened by a long-press.
    @State private var sendMenu = false
    /// Set by the long-press so the tap SwiftUI fires afterwards is swallowed.
    @State private var didLongPress = false

    private static func draftKey(_ chatID: String) -> String { "draft:" + chatID }

    /// How much of the account's usage limit is used, 0…1: the fullest of its
    /// windows. nil until the Mac has read the account's usage.
    private var limitFraction: Double? {
        let current = accounts.first(where: { $0.id == currentAccount }) ?? accounts.first
        guard let pct = current?.fullest() else { return nil }
        return min(1, max(0, Double(pct) / 100))
    }

    /// How full the conversation's memory is, 0…1, once a turn has reported it.
    private var memoryFraction: Double? {
        guard let context, context.window > 0 else { return nil }
        return min(1, Double(context.used) / Double(context.window))
    }

    private func memoryColour(_ f: Double) -> Color {
        f >= 0.9 ? Theme.danger : f >= 0.75 ? .orange : Theme.textTertiary
    }

    /// What a pointer's hover says over the logo (an iPad with a mouse).
    private var agentDetails: String {
        var lines = [provider == "codex" ? "Codex" : provider == "antigravity" ? "Antigravity" : "Claude Code"]
        if let f = limitFraction {
            lines.append("Usage limit \(Int(f * 100))%")
        }
        if let f = memoryFraction, let context {
            lines.append("Memory \(Int(f * 100))% · \(context.used / 1000)K of \(context.window / 1000)K")
        }
        lines.append(mini ? "Tap for agent, model, mode and account"
                     : settingsOpen ? "Tap to hide the settings" : "Tap for model, mode and account")
        return lines.joined(separator: "\n")
    }

    /// Every pill in one row. On a phone it scrolls sideways, to keep the
    /// composer one line tall; with an iPad's room it wraps onto a second line
    /// as the Mac's does, instead of running off the edge with Mode cut in
    /// half and Browser and Memory out of sight.
    @ViewBuilder
    private var pillRow: some View {
        if sizeClass == .regular {
            PillFlow(spacing: 8, lineSpacing: 6) { pills }
                .padding(.horizontal, 12)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { pills }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .padding(.horizontal, 12)
        }
    }

    private var agentName: String {
        provider == "codex" ? "Codex" : provider == "antigravity" ? "Antigravity" : "Claude Code"
    }
    private var currentAccountEntry: WireAccount? {
        guard accounts.count > 1 else { return nil }
        return accounts.first(where: { $0.id == currentAccount }) ?? accounts.first
    }
    private var modeLabel: String { Composer.modes.first { $0.id == mode }?.label ?? "Full" }
    private var memoryPercent: Int? {
        guard let context else { return nil }
        return min(100, Int((Double(context.used) / Double(max(1, context.window)) * 100).rounded()))
    }

    // MARK: The choices, shared by the pills and the mini composer's menu

    @ViewBuilder
    private var agentChoices: some View {
        Button { onProvider("claude") } label: {
            Label {
                Text(provider != "codex" && provider != "antigravity" ? "✓ Claude Code" : "Claude Code")
            } icon: { Image("ClaudeMark").renderingMode(.original) }
        }
        Button { onProvider("codex") } label: {
            Label {
                Text(provider == "codex" ? "✓ Codex" : "Codex")
            } icon: { Image("CodexMark").renderingMode(.template) }
        }
        // Google's agent (Gemini), the Mac's third. It was shown
        // when the Mac had put a conversation on it, and could
        // not be picked from here.
        Button { onProvider("antigravity") } label: {
            Label {
                Text(provider == "antigravity" ? "✓ Antigravity" : "Antigravity")
            } icon: { Image("AntigravityMark").renderingMode(.template) }
        }
    }

    @ViewBuilder
    private func accountChoices(_ current: WireAccount) -> some View {
        ForEach(accounts) { a in
            // Title and subtitle straight in the label: inside a
            // Label with a conditional icon, iOS showed the name
            // and dropped the usage line under it.
            Button { onAccount(a.id) } label: {
                Text(a.id == current.id ? "✓ \(a.name)" : a.name)
                Text(a.needsAuth != nil ? "Needs sign-in on the Mac"
                     : a.liveWindows().isEmpty ? "Usage not read yet"
                     : a.liveWindows().map { "\($0.label) \($0.percent)%" }.joined(separator: " · "))
            }
            .disabled(a.needsAuth != nil)
        }
    }

    @ViewBuilder
    private var modelChoices: some View {
        // What this conversation is actually on right now — the
        // family names below ("Opus") don't say which version.
        if let running = runningModel.flatMap(ModelName.pretty) {
            Section {
                Button {} label: { Label("Now running: \(running)", systemImage: "cpu") }
                    .disabled(true)
            }
        }
        ForEach(availableModels.filter { $0.older != true }) { m in
            modelButton(m)
        }
        // The Mac lists every version still available; the earlier
        // ones sit one level down so the current five stay in view.
        let older = availableModels.filter { $0.older == true }
        if !older.isEmpty {
            Menu("Older models") {
                ForEach(older) { m in modelButton(m) }
            }
        }
    }

    @ViewBuilder
    private var modeChoices: some View {
        ForEach(Composer.modes, id: \.id) { m in
            Button { mode = m.id } label: {
                Label { Text(m.label); Text(m.hint) } icon: { if mode == m.id { Image(systemName: "checkmark") } }
            }
        }
    }

    @ViewBuilder
    private func browserChoicesMenu(_ b: BrowserChoices) -> some View {
        ForEach(b.browsers) { option in
            Button { onBrowser(option.id) } label: {
                Label {
                    Text(option.name)
                    Text(option.id == "builtin" ? "The browser inside Superagent" : "On your Mac, with its sign-ins")
                } icon: { if b.current == option.id { Image(systemName: "checkmark") } }
            }
        }
    }

    /// The mini composer's one control: everything the pills hold, as the
    /// Mac's folded list is — one setting to a row, its name and its value,
    /// each opening its choices. Then the figures (usage, memory) last.
    @ViewBuilder
    private var settingsMenu: some View {
        Menu {
            agentChoices
        } label: {
            Text("Agent"); Text(agentName)
        }
        if let current = currentAccountEntry {
            Menu {
                accountChoices(current)
            } label: {
                Text("Account")
                Text(current.fullest().map { "\(current.shortName) · \($0)%" } ?? current.shortName)
            }
        }
        Menu {
            modelChoices
        } label: {
            Text("Model"); Text(modelPillLabel)
        }
        Menu {
            modeChoices
        } label: {
            Text("Mode"); Text(modeLabel)
        }
        if let b = browserChoices, b.browsers.count > 1 {
            Menu {
                browserChoicesMenu(b)
            } label: {
                Text("Browser"); Text(b.currentName)
            }
        }
        if limitFraction != nil || memoryPercent != nil {
            Section {
                if let f = limitFraction {
                    Button {} label: { Text("Usage limit \(Int(f * 100))%") }.disabled(true)
                }
                if let pct = memoryPercent, let context {
                    Button {} label: {
                        Text("Memory \(pct)%")
                        Text("\(context.used / 1000)K of \(context.window / 1000)K tokens")
                    }
                    .disabled(true)
                }
            }
        }
    }

    @ViewBuilder
    private var pills: some View {
                Menu {
                    agentChoices
                } label: {
                    ControlPill {
                        HStack(spacing: 4) {
                            ProviderMark(provider: provider, size: 13)
                            // A conversation the Mac put on Antigravity says
                            // so, rather than passing for Claude Code.
                            Text(agentName)
                            Image(systemName: "chevron.down").superFont(9, weight: .bold)
                        }
                    }
                }
                // Which subscription this chat spends, once there is more than
                // one: the Mac's Account pill, with each account's usage.
                if let current = currentAccountEntry {
                    Menu {
                        accountChoices(current)
                    } label: {
                        ControlPill {
                            HStack(spacing: 4) {
                                if !compact { Text("Account").foregroundStyle(Theme.textTertiary) }
                                Text(current.shortName)
                                if let pct = current.fullest() {
                                    Text("\(pct)%").foregroundStyle(usageColour(pct)).monospacedDigit()
                                }
                                Image(systemName: "chevron.down").superFont(9, weight: .bold)
                            }
                        }
                    }
                    .accessibilityIdentifier("account-pill")
                }
                Menu {
                    modelChoices
                } label: {
                    ControlPill { HStack(spacing: 4) { if !compact { Text("Model").foregroundStyle(Theme.textTertiary) }; Text(modelPillLabel); Image(systemName: "chevron.down").superFont(9, weight: .bold) } }
                }
                Menu {
                    modeChoices
                } label: {
                    ControlPill { HStack(spacing: 4) { if !compact { Text("Mode").foregroundStyle(Theme.textTertiary) }; Text(modeLabel); Image(systemName: "chevron.down").superFont(9, weight: .bold) } }
                }
                if let b = browserChoices, b.browsers.count > 1 {
                    Menu {
                        browserChoicesMenu(b)
                    } label: {
                        ControlPill { HStack(spacing: 4) { if !compact { Text("Browser").foregroundStyle(Theme.textTertiary) }; Text(b.currentName); Image(systemName: "chevron.down").superFont(9, weight: .bold) } }
                    }
                    .accessibilityIdentifier("browser-pill")
                }
                if let context, let pct = memoryPercent {
                    // The desktop's Memory gauge, at pill size: how much of the
                    // context window the conversation is carrying.
                    HStack(spacing: 5) {
                        if !compact { Text("Memory").foregroundStyle(Theme.textTertiary) }
                        Capsule().fill(Theme.accentSoft)
                            .frame(width: 36, height: 4)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(pct >= 75 ? Theme.needsYou : Theme.textSecondary)
                                        .frame(width: geo.size.width * Double(pct) / 100)
                                }
                            }
                        Text("\(pct)%").foregroundStyle(Theme.textSecondary).monospacedDigit()
                    }
                    .superFont(12, weight: .medium)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.panel, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Memory \(pct) percent — \(context.used) of \(context.window) tokens")
                }
    }

    private func loadDraft() {
        guard draft.isEmpty else { return }
        draft = UserDefaults.standard.string(forKey: Self.draftKey(chatID)) ?? ""
    }

    private func saveDraft() {
        let key = Self.draftKey(chatID)
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(draft, forKey: key)
        }
    }

    /// Send the Mac what is typed, a moment after the typing pauses — at once
    /// when the field was emptied, so a message that has been sent is not
    /// still sitting in the Mac's composer.
    private func scheduleDraftPush() {
        draftPush?.cancel()
        let chat = chatID
        guard DraftSync.normalized(draft) != DraftSync.synced(chat) else { return }
        draftPush = Task { @MainActor in
            if !DraftSync.normalized(draft).isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled, chat == chatID else { return }
            let text = DraftSync.normalized(draft)
            if await pushDraft(text) { DraftSync.setSynced(text, chatID: chat) }
        }
    }

    /// The Mac said what its composer holds.
    private func applyRemoteDraft(_ remote: Connection.RemoteDraft?) {
        guard let remote else { return }
        switch DraftSync.incoming(remote.text, local: draft, synced: DraftSync.synced(chatID)) {
        case .agree:
            DraftSync.setSynced(remote.text, chatID: chatID)
        case .take(let text):
            // Marked as agreed first: assigning the field runs its own change
            // handler, which would otherwise send these words straight back.
            DraftSync.setSynced(text, chatID: chatID)
            draft = text
        case .keepAndPush:
            scheduleDraftPush()
        }
    }

    /// Add the image currently on the iOS pasteboard through the same
    /// downscaling/encoding path as Photo Library attachments.
    private func pasteImage() {
        guard let image = UIPasteboard.general.image,
              let data = image.jpegData(compressionQuality: 0.9),
              let attachment = Attachment(imageData: data)
        else { return }
        attachments.append(attachment)
        Haptics.tap()
    }

    /// Send from the composer: clear here, hand the text up. The second clear a
    /// run-loop turn later is for an uncommitted autocorrect suggestion — UIKit
    /// still owns marked text at send and puts its buffer back over the first
    /// assignment, so the words stayed while the message went. Guarded so it can
    /// never eat something typed in between.
    private func submit() {
        let text = draft
        // With a hardware keyboard the cursor comes back whichever way the
        // message went — Return, or Send pressed with the trackpad, which took
        // focus off the box on its way and left the next message a tap away.
        let wasTyping = focused.wrappedValue || KeyboardRoom.hardwareAttached
        dictationSpent = true
        draft = ""
        saveDraft()
        onSend(text)
        // A hardware Return key resigns first responder as its own default
        // UIKit behavior on iPad, a run-loop turn after this closure returns —
        // after `.onKeyPress` already marked the key `.handled`, so it's not
        // something that guard prevents. Re-assert focus once that's had its
        // turn, or every hardware-keyboard send left the field needing a tap.
        //
        // More than once, and only when it has actually been lost: UIKit can
        // let go a beat later than one turn, and setting focus while it still
        // reads as held does nothing — which is how the cursor still went
        // missing after Return. Never for a send made without the keyboard up.
        Task { @MainActor in
            if !draft.isEmpty {
                draft = ""
                saveDraft()
            }
            guard wasTyping else { return }
            for wait in [0, 60, 200, 450] {
                if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
                if !focused.wrappedValue { focused.wrappedValue = true }
            }
        }
    }

    /// Hold Send while the agent is working to send AFTER it finishes, instead
    /// of interjecting mid-task. Captures the text, clears the composer, and
    /// hands it to the Mac to hold — the pill above shows what's waiting, but
    /// it's the Mac's turn-end, not this phone, that actually sends it.
    /// Text only — an attachment mid-run is rare and the composer's images live
    /// on ChatView, which send() reads at flush time anyway.
    private func holdForLater() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Nothing running to wait for → just send it now. (The Mac applies the
        // same rule if this phone's `working` is a moment stale.)
        guard working else { submit(); return }
        onQueue(text)
        dictationSpent = true
        draft = ""
        saveDraft()
        Haptics.tap()
    }

    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || !files.isEmpty)
    }
    private var slashQuery: String? {
        guard draft.hasPrefix("/"), !draft.contains(" "), !commands.isEmpty else { return nil }
        return String(draft.dropFirst())
    }
    private var matchingCommands: [String] {
        guard let q = slashQuery else { return [] }
        return commands.filter { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }.prefix(6).map { $0 }
    }
    /// "Opus 5.5" when the session says which it's on and it's the family picked
    /// (or Default); otherwise the picked entry's own label.
    private var modelPillLabel: String {
        let picked = availableModels.first { $0.id == model }?.label ?? "Default"
        guard let running = runningModel, let short = ModelName.pretty(running, context: false) else { return picked }
        if model.isEmpty || short.lowercased().hasPrefix(picked.lowercased()) { return short }
        return picked
    }

    private var availableModels: [WireModelOption] {
        // Claude's models are only Claude's: Codex and Antigravity list their
        // own once a session has reported them, and offer Default until then.
        if provider != "codex" && provider != "antigravity" && sessionModels.isEmpty { return Self.models }
        // Claude's list carries its own Default entry; Codex's doesn't.
        if sessionModels.contains(where: { $0.id.isEmpty }) { return sessionModels }
        return [.init(id: "", label: "Default", hint: "Whatever your account uses")] + sessionModels
    }
    private var providerName: String { provider == "codex" ? "Codex" : provider == "antigravity" ? "Antigravity" : "Claude" }

    private func modelButton(_ m: WireModelOption) -> some View {
        Button { model = m.id } label: {
            Label { Text(m.label); Text(m.hint) } icon: { if model == m.id { Image(systemName: "checkmark") } }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if !heldSends.isEmpty {
                VStack(spacing: 4) {
                    ForEach(heldSends) { m in
                        HStack(spacing: 8) {
                            Image(systemName: "clock").superFont(12).foregroundStyle(Theme.accent)
                            Text(m.text).superFont(13).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("sends when done").superFont(11).foregroundStyle(Theme.textTertiary)
                            Button { onCancelQueue(m.id) } label: {
                                Image(systemName: "xmark.circle.fill").superFont(13).foregroundStyle(Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
                    }
                }
                .padding(.horizontal, 12)
            }
            if !matchingCommands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matchingCommands, id: \.self) { c in
                            Button { draft = "/\(c) "; Haptics.tap() } label: {
                                Text("/" + c).superFont(12.5, weight: .medium, design: .monospaced)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            if !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(files) { f in
                            HStack(spacing: 6) {
                                Image(systemName: "doc").superFont(12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).superFont(12, weight: .medium).lineLimit(1)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(f.data.count), countStyle: .file))
                                        .superFont(10.5).foregroundStyle(Theme.textTertiary)
                                }
                                Button { files.removeAll { $0.id == f.id } } label: {
                                    Image(systemName: "xmark.circle.fill").superFont(13)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { a in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: a.thumbnail).resizable().scaledToFill()
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button { attachments.removeAll { $0.id == a.id } } label: {
                                    Image(systemName: "xmark.circle.fill").superFont(16)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button(action: pasteImage) {
                        Label("Paste Image", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!UIPasteboard.general.hasImages)
                    Button { showPhotoPicker = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
                    Button { showFilePicker = true } label: { Label("Choose a File", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus").superFont(15, weight: .semibold)
                        .frame(width: well, height: well)
                        .background(Theme.accentSoft, in: Circle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Attach")
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems,
                              maxSelectionCount: 10, matching: .images)
                .fileImporter(isPresented: $showFilePicker,
                              allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                    guard case let .success(urls) = result else { return }
                    for url in urls.prefix(4) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        guard let data = try? Data(contentsOf: url), data.count <= 25 * 1024 * 1024 else { continue }
                        files.append(PickedFile(name: url.lastPathComponent, data: data))
                    }
                }

                HStack(alignment: .bottom, spacing: 0) {
                    if mini {
                        // Mini (a split window, a narrow column): the logo is
                        // the only control, and it opens every setting as a
                        // menu instead of laying pills out under the box.
                        Menu {
                            settingsMenu
                        } label: {
                            logoMark(highlighted: false)
                        }
                        .menuOrder(.fixed)
                        .buttonStyle(.plain)
                        .help(agentDetails)
                        .accessibilityValue(limitFraction.map { "Usage limit \(Int($0 * 100)) percent" } ?? "")
                        .padding(.leading, 3)
                        .accessibilityLabel("Agent, model and mode")
                        .accessibilityIdentifier("composer-settings")
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { settingsOpen.toggle() }
                            Haptics.tap()
                        } label: {
                            logoMark(highlighted: settingsOpen)
                        }
                        .buttonStyle(.plain)
                        .help(agentDetails)
                        .accessibilityValue(limitFraction.map { "Usage limit \(Int($0 * 100)) percent" } ?? "")
                        .padding(.leading, 3)
                        .accessibilityLabel(settingsOpen ? "Hide agent, model and mode" : "Show agent, model and mode")
                        .accessibilityIdentifier("composer-settings")
                    }
                    TextField(dictation.listening ? "Listening…" : "Message \(providerName)…", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .superFont(15.5)
                        .textFieldStyle(.plain)
                        // Off, not just spellcheck: on iPadOS with a hardware
                        // keyboard attached, autocorrection is what draws the
                        // QuickType suggestion strip above the keys. A coding
                        // agent's prompts are not prose it should be guessing
                        // at, so leaving it on made the strip is pure clutter.
                        .autocorrectionDisabled()
                        .focused(focused)
                        // A hardware keyboard's Return sends, as it does on the
                        // Mac. A vertical-axis TextField treats Return as a
                        // newline and never fires onSubmit, so on an iPad with
                        // a keyboard there was NO way to send by key at all.
                        // Shift+Return keeps the newline, same as the desktop.
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            else { return .ignored }
                            submit()
                            return .handled
                        }
                        .padding(.leading, 4).padding(.trailing, 6).padding(.vertical, 9)
                    Button {
                        Task { if dictation.listening { dictation.stop() } else { await dictation.start() } }
                    } label: {
                        Image(systemName: dictation.listening ? "waveform.circle.fill" : "mic")
                            .superFont(15, weight: .medium)
                            .foregroundStyle(dictation.listening ? Theme.danger : Theme.textTertiary)
                            .frame(width: well, height: well)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.listening ? "Stop dictation" : "Dictate")
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))

                if working {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill").superFont(13, weight: .bold)
                            .frame(width: well, height: well)
                            .background(Theme.accentSoft, in: Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Stop")
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                Button {
                    // A long-press opened the menu; swallow the tap that follows.
                    if didLongPress { didLongPress = false; return }
                    submit()
                } label: {
                    Image(systemName: "arrow.up").superFont(15, weight: .bold)
                        .frame(width: well, height: well)
                        .background(canSend ? Theme.accent : Theme.accentSoft, in: Circle())
                        .foregroundStyle(canSend ? Theme.accentFg : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityLabel("Send")
                // A tap sends now. A long-press opens a small inline menu to
                // choose "send now" vs "send when it finishes" — inline, not a
                // system context menu, so the keyboard stays up. Both options
                // always show; "when it finishes" just sends now if nothing is
                // running (see holdForLater).
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        guard canSend else { return }
                        didLongPress = true
                        sendMenu = true
                        Haptics.tap()
                    }
                )
                .overlay(alignment: .bottomTrailing) {
                    if sendMenu {
                        SendMenu(
                            onLater: { sendMenu = false; holdForLater() },
                            onNow: { sendMenu = false; submit() },
                            onDismiss: { sendMenu = false }
                        )
                        .offset(y: -(well + 8))
                    }
                }
            }
            .padding(.horizontal, 12)

            // Every pill belongs to the same strip. Memory used to sit outside
            // this ScrollView and stay pinned over Model/Mode on narrow phones.
            // Mini: never a row of pills under the box; they are in the logo's menu.
            if settingsOpen && !mini { pillRow.transition(.opacity.combined(with: .move(edge: .bottom))) }
            if let e = dictation.error { Text(e).superFont(11).foregroundStyle(Theme.danger).lineLimit(1) }
        }
        .padding(.top, 8).padding(.bottom, 8)
        .background(Theme.content)
        // Only an iPad folds by width; a phone never measures at all.
        .onGeometryChange(for: Bool.self) { proxy in
            sizeClass == .regular && proxy.size.width > 0 && proxy.size.width < Self.miniWidth
        } action: { narrow = $0 }
        .onAppear { loadDraft() }
        .onDisappear { saveDraft() }
        // Reused across a chat switch: keep the old chat's words, load the new
        // chat's. (id is set on ChatView today, so this is belt-and-braces.)
        .onChange(of: remoteDraft) { _, r in applyRemoteDraft(r) }
        .onChange(of: chatID) { old, _ in
            draftPush?.cancel()
            let key = Self.draftKey(old)
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(draft, forKey: key)
            }
            draft = UserDefaults.standard.string(forKey: Self.draftKey(chatID)) ?? ""
        }
        .onChange(of: draft) { _, _ in
            saveDraft()
            scheduleDraftPush()
        }
        .onChange(of: dictation.transcript) { _, t in
            guard !dictationSpent else { return }
            if !t.isEmpty { draft = t }
        }
        .onChange(of: dictation.listening) { _, on in if on { dictationSpent = false } }
    }
}

/// A file picked for the agent: kept whole until send, then uploaded to the
/// Mac in slices and handed over as a path.
struct PickedFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let data: Data
}

/// The agent's brand mark — Claude's spark (its own orange) for Claude, Codex's
/// own mark (OpenAI's blossom as a cloud with a >_ prompt, tinted) for Codex,
/// Antigravity's arch (tinted) for Antigravity — so which backend a chat runs
/// on is legible at a glance, in the Agent pill and its menu. Assets are the
/// real vector paths (Simple Icons / LobeHub) in the catalog (ClaudeMark /
/// CodexMark / AntigravityMark), not redrawn.
struct ProviderMark: View {
    let provider: String
    var size: CGFloat = 14
    var body: some View {
        if provider == "codex" {
            Image("CodexMark").renderingMode(.template).resizable().scaledToFit()
                .frame(width: size, height: size).foregroundStyle(Theme.textSecondary)
        } else if provider == "antigravity" {
            Image("AntigravityMark").renderingMode(.template).resizable().scaledToFit()
                .frame(width: size, height: size).foregroundStyle(Theme.textSecondary)
        } else {
            Image("ClaudeMark").renderingMode(.original).resizable().scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

/// The little "send now / send when it finishes" menu shown on a long-press of
/// Send. Inline (an overlay), not a system context menu, so the keyboard is not
/// dismissed while you decide.
private struct SendMenu: View {
    let onLater: () -> Void
    let onNow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onLater) {
                Label("Send when it finishes", systemImage: "clock")
                    .superFont(14).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            Divider()
            Button(action: onNow) {
                Label("Send now", systemImage: "arrow.up")
                    .superFont(14).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 230)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        // Tap anywhere else to dismiss, without stealing the keyboard.
        .background(
            Color.clear
                .frame(width: 3000, height: 3000)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
        )
        .fixedSize()
    }
}


/// Lays its children out left to right, starting a new line when one does not
/// fit — the Mac's pill row, which wraps rather than scrolls.
struct PillFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { y += line + lineSpacing; x = 0; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
