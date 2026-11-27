import SwiftUI

/// A project's Conductor as the Mac's Sessions tab shows it: the numbered sessions with where each
/// stands, and the Confirm / Auto switch for how Main routes your messages.
struct ConductorSessionsView: View {
    let connection: Connection
    let workspace: WireWorkspace
    /// Open a conversation (a session, or Main).
    let open: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var state: WireConductorState?
    @State private var error: String?
    @State private var selected: String?

    private var live: [WireConductorSession] {
        (state?.sessions ?? [])
            .filter { $0.status != "closed" }
            .sorted { SessionLook.rank($0) != SessionLook.rank($1) ? SessionLook.rank($0) < SessionLook.rank($1) : ($0.ticket ?? 0) < ($1.ticket ?? 0) }
    }
    private var current: WireConductorSession? {
        live.first { $0.chatId == selected } ?? live.first
    }
    private var needing: Int { live.filter { $0.status == "needs-you" }.count }
    private var working: Int { live.filter { $0.status == "working" }.count }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 18)
            if let state {
                ScrollView {
                    VStack(spacing: 0) {
                        if live.isEmpty {
                            empty
                        } else {
                            dots
                            if let s = current { detail(s) }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Talk to Main and the routing switch stay put under whatever scrolls.
                footer(state)
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
                    .background(Theme.content)
            } else if let error {
                Spacer()
                Text(error).superFont(13).foregroundStyle(Theme.textSecondary)
                Spacer()
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .background(Theme.content)
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        // The Mac changes as agents work; look again while this is open.
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conductor").superFont(20, weight: .bold).foregroundStyle(Theme.textPrimary)
                Text(summaryLine).superFont(12.5).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Done") { dismiss() }.superFont(15, weight: .semibold)
        }
        .padding(.top, 22).padding(.bottom, 14)
    }

    private var summaryLine: String {
        if live.isEmpty { return "No sessions yet" }
        var bits = ["\(live.count) \(live.count == 1 ? "session" : "sessions")"]
        if needing > 0 { bits.append("\(needing) \(needing == 1 ? "needs" : "need") you") }
        if working > 0 { bits.append("\(working) working") }
        return bits.joined(separator: " · ")
    }

    /// One dot per session: its number in a ring that says how it is doing. Tap one to see it below.
    private var dots: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 60), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(live) { s in
                SessionDot(session: s, selected: s.chatId == current?.chatId)
                    .onTapGesture { Haptics.tap(); withAnimation(.snappy(duration: 0.2)) { selected = s.chatId } }
                    .accessibilityIdentifier("conductor-dot-\(s.chatId)")
                    // Main spawned it: the dot pops in from nothing.
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: live.map(\.chatId))
        .onChange(of: live.map(\.chatId)) { old, new in
            if !old.isEmpty, new.count > old.count { Haptics.tap() }
        }
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func detail(_ s: WireConductorSession) -> some View {
        let look = SessionLook(s)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let k = s.trackerKey {
                    Text(k).superFont(13, weight: .semibold).monospacedDigit().foregroundStyle(look.tint)
                }
                Text(s.titleWithoutKey.isEmpty ? "Untitled" : s.titleWithoutKey)
                    .superFont(17, weight: .semibold).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Spacer(minLength: 4)
                Text(look.word).superFont(12, weight: .semibold).foregroundStyle(look.tint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(look.tint.opacity(0.14), in: Capsule())
            }
            if let a = s.approval {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wants to").superFont(11, weight: .medium).foregroundStyle(Theme.textSecondary)
                    Text(a.preview).superFont(13.5).foregroundStyle(Theme.textPrimary).lineLimit(3)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.needsYou.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if !s.summary.isEmpty {
                Text(s.summary).superFont(14).foregroundStyle(Theme.textSecondary).lineLimit(4)
            }
            chips(s)
            Button { open(s.chatId) } label: {
                Text(s.status == "needs-you" ? "Open to answer" : "Open session")
                    .superFont(15, weight: .semibold)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(s.status == "needs-you" ? Color.black : Theme.textPrimary)
                    .background(s.status == "needs-you" ? Theme.needsYou : Theme.panel,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(s.status == "needs-you" ? Color.clear : Theme.border))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conductor-open-session")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
        .id(s.chatId)
        .transition(.opacity)
    }

    @ViewBuilder
    private func chips(_ s: WireConductorSession) -> some View {
        let files = s.files?.count ?? 0
        let unmerged = s.unmerged ?? 0
        if s.branch != nil || files > 0 || unmerged > 0 {
            HStack(spacing: 10) {
                if let b = s.branch { HStack(spacing: 4) { Image(systemName: "arrow.triangle.branch"); Text(b).lineLimit(1) } }
                if unmerged > 0 { Text("\(unmerged) unmerged") }
                if files > 0 { Text("\(files) \(files == 1 ? "file" : "files")") }
            }
            .superFont(12).foregroundStyle(Theme.textTertiary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up").superFont(26).foregroundStyle(Theme.textTertiary)
            Text("Tell Main what you want done").superFont(15, weight: .semibold).foregroundStyle(Theme.textPrimary)
            Text("It starts a session for each piece of work, and they show up here.")
                .superFont(13).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    /// Talk to Main, and how it routes: one row.
    private func footer(_ state: WireConductorState) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { open(state.chatId) } label: {
                    Label("Talk to Main", systemImage: "bubble.left.and.text.bubble.right")
                        .superFont(14.5, weight: .semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.panel, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("conductor-talk-to-main")
                Picker("Routing", selection: Binding(get: { state.routing }, set: { setRouting($0) })) {
                    Text("Confirm").tag("confirm")
                    Text("Auto").tag("auto")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .accessibilityIdentifier("conductor-routing")
            }
            Text(state.routing == "auto"
                 ? "Auto: Main starts and routes sessions itself."
                 : "Confirm: Main asks before starting or routing.")
                .superFont(11.5).foregroundStyle(Theme.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
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

/// How a session reads: its colour, its word, and where it sorts (needs you, working, the rest).
private struct SessionLook {
    let tint: Color
    let word: String
    init(_ s: WireConductorSession) {
        switch s.status {
        case "needs-you": tint = Theme.needsYou; word = "Needs you"
        case "working": tint = Theme.working; word = "Working"
        default: tint = Theme.textTertiary; word = "Idle"
        }
    }
    static func rank(_ s: WireConductorSession) -> Int { s.status == "needs-you" ? 0 : s.status == "working" ? 1 : 2 }
}

/// A session as a dot: its number inside a ring. Green and turning while it works, amber and
/// breathing when it needs you, grey when it is idle. The chosen one is filled.
private struct SessionDot: View {
    let session: WireConductorSession
    let selected: Bool
    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        let look = SessionLook(session)
        ZStack {
            Circle().fill(look.tint.opacity(selected ? 0.28 : 0.12))
            Circle().stroke(look.tint.opacity(session.status == "working" ? 0.25 : 0.9), lineWidth: selected ? 2.5 : 1.5)
            if session.status == "working" {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(look.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            }
            Text(session.trackerKey?.split(separator: "-").last.map(String.init) ?? "")
                .superFont(15, weight: .semibold).monospacedDigit()
                .foregroundStyle(selected ? Theme.textPrimary : look.tint)
        }
        .frame(width: 52, height: 52)
        .scaleEffect(session.status == "needs-you" && breathe ? 1.07 : 1)
        .animation(session.status == "needs-you" ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: breathe)
        .onAppear { spin = true; breathe = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.title), \(look.word)")
        .accessibilityAddTraits(.isButton)
    }
}
