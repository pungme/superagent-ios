import PhotosUI
import SwiftUI

/// The desktop composer, sized for a thumb: attachments above, the field with
/// a mic and a send button, and the Model / Mode pills underneath. Typing "/"
/// opens the commands the agent reported for this session.
struct Composer: View {
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    @Binding var pickerItems: [PhotosPickerItem]
    let dictation: Dictation
    let sending: Bool
    let connected: Bool
    let working: Bool
    let commands: [String]
    @Binding var model: String
    @Binding var mode: String
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool

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

    private var canSend: Bool {
        connected && !sending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
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
                                Text("/" + c).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
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
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 16))
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
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Theme.accentSoft, in: Circle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Add a photo")

                HStack(alignment: .bottom, spacing: 6) {
                    TextField(dictation.listening ? "Listening…" : "Message Claude…", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .font(.system(size: 15.5))
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .padding(.leading, 12).padding(.vertical, 9)
                    Button {
                        Task { if dictation.listening { dictation.stop() } else { await dictation.start() } }
                    } label: {
                        Image(systemName: dictation.listening ? "waveform.circle.fill" : "mic")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(dictation.listening ? Theme.danger : Theme.textTertiary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.listening ? "Stop dictation" : "Dictate")
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))

                if working {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Theme.accentSoft, in: Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Stop")
                }
                Button(action: onSend) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(canSend ? Theme.accent : Theme.accentSoft, in: Circle())
                        .foregroundStyle(canSend ? Theme.accentFg : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Menu {
                    ForEach(Composer.models, id: \.id) { m in
                        Button { model = m.id } label: {
                            Label { Text(m.label); Text(m.hint) } icon: { if model == m.id { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    ControlPill { HStack(spacing: 4) { Text("Model").foregroundStyle(Theme.textTertiary); Text(Composer.models.first { $0.id == model }?.label ?? "Default"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) } }
                }
                Menu {
                    ForEach(Composer.modes, id: \.id) { m in
                        Button { mode = m.id } label: {
                            Label { Text(m.label); Text(m.hint) } icon: { if mode == m.id { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    ControlPill { HStack(spacing: 4) { Text("Mode").foregroundStyle(Theme.textTertiary); Text(Composer.modes.first { $0.id == mode }?.label ?? "Full"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) } }
                }
                Spacer()
                if let e = dictation.error { Text(e).font(.system(size: 11)).foregroundStyle(Theme.danger).lineLimit(1) }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8).padding(.bottom, 8)
        .background(Theme.content)
    }
}
