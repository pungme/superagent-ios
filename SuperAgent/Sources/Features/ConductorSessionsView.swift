import SwiftUI

/// A project's Conductor as the Mac's Sessions tab shows it: the numbered sessions with where each
/// stands, and the Confirm / Auto switch for how Main routes your messages.
struct ConductorSessionsView: View {
    let connection: Connection
    let workspace: WireWorkspace
    /// Open a session's conversation.
    let open: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var state: WireConductorState?
    @State private var error: String?

    private var live: [WireConductorSession] {
        (state?.sessions ?? [])
            .filter { $0.status != "closed" }
            .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.updatedAt > $1.updatedAt }
    }
    /// Those that need you first, then those at work, then the rest.
    private func rank(_ s: WireConductorSession) -> Int { s.status == "needs-you" ? 0 : s.status == "working" ? 1 : 2 }

    var body: some View {
        NavigationStack {
            List {
                if let state {
                    Section {
                        Picker("Routing", selection: Binding(
                            get: { state.routing },
                            set: { setRouting($0) }
                        )) {
                            Text("Confirm").tag("confirm")
                            Text("Auto").tag("auto")
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                        .accessibilityIdentifier("conductor-routing")
                    } footer: {
                        Text(state.routing == "auto"
                             ? "Main starts and routes sessions on its own, and asks only when it is unsure."
                             : "Main asks before it starts a session or sends your message to one.")
                            .superFont(12)
                    }
                    Section {
                        Button { open(state.chatId) } label: {
                            Label("Talk to Main", systemImage: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .accessibilityIdentifier("conductor-talk-to-main")
                    }
                    if live.isEmpty {
                        Section {
                            VStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up").superFont(22).foregroundStyle(Theme.textTertiary)
                                Text("No sessions yet").superFont(14, weight: .semibold).foregroundStyle(Theme.textPrimary)
                                Text("Tell Main what you want done. It starts a session for each piece of work.")
                                    .superFont(12).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section("\(live.count) \(live.count == 1 ? "session" : "sessions")") {
                            ForEach(live) { s in SessionRow(session: s) { open(s.chatId) } }
                        }
                    }
                } else if let error {
                    Text(error).foregroundStyle(Theme.textSecondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.content)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            // The Mac changes as agents work; look again while this is open.
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(4))
                }
            }
        }
    }

    private func load() async {
        do {
            state = try await connection.conductorState(workspaceId: workspace.id)
            error = nil
        } catch {
            if state == nil { self.error = "Could not load the sessions." }
        }
    }

    private func setRouting(_ mode: String) {
        state?.routing = mode
        Haptics.tap()
        Task { try? await connection.conductorSetRouting(workspaceId: workspace.id, routing: mode) }
    }
}

private struct SessionRow: View {
    let session: WireConductorSession
    let tap: () -> Void

    private var tint: Color {
        switch session.status {
        case "needs-you": return Theme.needsYou
        case "working": return Theme.working
        default: return Theme.textTertiary
        }
    }
    private var word: String {
        switch session.status {
        case "needs-you": return "Needs you"
        case "working": return "Working"
        default: return "Idle"
        }
    }

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let t = session.ticket {
                        Text("#\(t)").superFont(12, weight: .semibold).monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.panel, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                    Text(session.title.isEmpty ? "Untitled" : session.title)
                        .superFont(15, weight: .semibold).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    Spacer(minLength: 6)
                    HStack(spacing: 5) {
                        if session.status == "working" { ProgressView().controlSize(.mini) }
                        else { Circle().fill(tint).frame(width: 7, height: 7) }
                        Text(word).superFont(12, weight: .medium).foregroundStyle(tint)
                    }
                }
                if let a = session.approval {
                    Text(a.preview).superFont(12.5).lineLimit(2)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.needsYou.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if !session.summary.isEmpty {
                    Text(session.summary).superFont(13).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                chips
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conductor-session-\(session.ticket ?? 0)")
    }

    @ViewBuilder
    private var chips: some View {
        let files = session.files?.count ?? 0
        let unmerged = session.unmerged ?? 0
        if session.branch != nil || files > 0 || unmerged > 0 {
            HStack(spacing: 10) {
                if let b = session.branch {
                    HStack(spacing: 4) { Image(systemName: "arrow.triangle.branch"); Text(b).lineLimit(1) }
                }
                if unmerged > 0 { Text("\(unmerged) unmerged") }
                if files > 0 { Text("\(files) \(files == 1 ? "file" : "files")") }
            }
            .superFont(11.5).foregroundStyle(Theme.textTertiary)
        }
    }
}
