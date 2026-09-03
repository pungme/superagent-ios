import PhotosUI
import SwiftUI

/// The desktop composer, sized for a thumb: attachments above, the field with
/// a mic and a send button, and the Model / Mode pills underneath. Typing "/"
/// opens the commands the agent reported for this session.
struct Composer: View {
    /// The round icon buttons hold a glyph that grows with the text size;
    /// the well has to grow with it or the glyph spills over the circle. It
    /// stops growing at 46 pt, and the glyphs stop at .accessibility1, because
    /// past that the three wells eat the whole row and there is nowhere left to
    /// type — the message field and the transcript keep scaling without them.
    @ScaledMetric(relativeTo: .subheadline) private var wellMetric: CGFloat = 34
    private var well: CGFloat { min(wellMetric, 46) }

    @Binding var draft: String
    @Binding var attachments: [Attachment]
    @Binding var pickerItems: [PhotosPickerItem]
    /// Files on their way to the agent — anything, not just pictures.
    @Binding var files: [PickedFile]
    let dictation: Dictation
    let connected: Bool
    let working: Bool
    let commands: [String]
    /// Live context and the window it lives in, when a turn has reported one.
    let context: (used: Int, window: Int)?
    @Binding var model: String
    @Binding var mode: String
    /// Which agent this conversation runs on, and how to move it. Codex exposes
    /// its account default here; permission modes are shared by both agents.
    let provider: String
    let onProvider: (String) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    /// Owned by ChatView. The chat needs to know when the keyboard is up: it
    /// gives the docked page's room back to the transcript, pauses the mirror,
    /// and lets a tap on the transcript put the keyboard away. A private
    /// @FocusState here left all three dead, since nothing outside could see it.
    var focused: FocusState<Bool>.Binding

    static let models: [(id: String, label: String, hint: String)] = [
        ("", "Default", "Whatever your account uses"),
        ("opus", "Opus", "Deepest reasoning"),
        ("sonnet", "Sonnet", "Fast and capable"),
        ("haiku", "Haiku", "Quickest, cheapest")
    ]
    static let modes: [(id: String, label: String, hint: String)] = [
        ("bypassPermissions", "Full", "Runs commands and edits, like your terminal"),
        ("ask", "Ask", "Asks before commands and edits — you approve here"),
        ("acceptEdits", "Edits", "Applies file edits; some commands may be refused"),
        ("plan", "Plan", "Read-only — plans without changing anything")
    ]

    @State private var showPhotoPicker = false
    @State private var showFilePicker = false

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

    var body: some View {
        VStack(spacing: 8) {
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

                HStack(alignment: .bottom, spacing: 6) {
                    TextField(dictation.listening ? "Listening…" : "Message Claude…", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .superFont(15.5)
                        .textFieldStyle(.plain)
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
                            onSend()
                            return .handled
                        }
                        .padding(.leading, 12).padding(.vertical, 9)
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
                Button(action: onSend) {
                    Image(systemName: "arrow.up").superFont(15, weight: .bold)
                        .frame(width: well, height: well)
                        .background(canSend ? Theme.accent : Theme.accentSoft, in: Circle())
                        .foregroundStyle(canSend ? Theme.accentFg : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                // Same reasoning as the project bar: at the accessibility sizes
                // two pills no longer fit across a phone, and "M… D…" tells you
                // nothing about which model you are on.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                Menu {
                    Button { onProvider("claude") } label: {
                        Label { Text("Claude Code") } icon: { if provider != "codex" { Image(systemName: "checkmark") } }
                    }
                    Button { onProvider("codex") } label: {
                        Label { Text("Codex") } icon: { if provider == "codex" { Image(systemName: "checkmark") } }
                    }
                } label: {
                    ControlPill {
                        HStack(spacing: 4) {
                            Text("Agent").foregroundStyle(Theme.textTertiary)
                            Text(provider == "codex" ? "Codex" : "Claude Code")
                            Image(systemName: "chevron.down").superFont(9, weight: .bold)
                        }
                    }
                }
                Menu {
                    ForEach(provider == "codex" ? Array(Composer.models.prefix(1)) : Composer.models, id: \.id) { m in
                        Button { model = m.id } label: {
                            Label { Text(m.label); Text(m.hint) } icon: { if model == m.id { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    ControlPill { HStack(spacing: 4) { Text("Model").foregroundStyle(Theme.textTertiary); Text(provider == "codex" ? "Default" : (Composer.models.first { $0.id == model }?.label ?? "Default")); Image(systemName: "chevron.down").superFont(9, weight: .bold) } }
                }
                Menu {
                    ForEach(Composer.modes, id: \.id) { m in
                        Button { mode = m.id } label: {
                            Label { Text(m.label); Text(m.hint) } icon: { if mode == m.id { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    ControlPill { HStack(spacing: 4) { Text("Mode").foregroundStyle(Theme.textTertiary); Text(Composer.modes.first { $0.id == mode }?.label ?? "Full"); Image(systemName: "chevron.down").superFont(9, weight: .bold) } }
                }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                if let context {
                    let pct = min(100, Int((Double(context.used) / Double(max(1, context.window)) * 100).rounded()))
                    // The desktop's Memory gauge, at pill size: how much of the
                    // context window the conversation is carrying.
                    HStack(spacing: 5) {
                        Text("Memory").foregroundStyle(Theme.textTertiary)
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
                if let e = dictation.error { Text(e).superFont(11).foregroundStyle(Theme.danger).lineLimit(1) }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8).padding(.bottom, 8)
        .background(Theme.content)
    }
}

/// A file picked for the agent: kept whole until send, then uploaded to the
/// Mac in slices and handed over as a path.
struct PickedFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let data: Data
}
