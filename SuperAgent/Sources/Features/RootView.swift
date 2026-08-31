import SwiftUI
import os

private let log = Logger(subsystem: "dev.superagent.ios", category: "app")

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var showPair = false
    @State private var showSettings = false
    /// A pairing link opened from outside (AirDrop, Messages, a tapped QR) skips the scanner.
    @State private var incomingPair: PairPayload?
    @State private var path = NavigationPath()
    /// An iPad, or an iPhone in landscape that is wide enough to hold two
    /// columns. The Mac's window is a sidebar and the thing you are working on;
    /// with the room to do the same, do the same.
    @Environment(\.horizontalSizeClass) private var width
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if let machine = app.selected {
                let c = app.connection(for: machine)
                if width == .regular { split(c) } else { stack(c) }
            } else {
                NavigationStack { WelcomeView(onPair: { showPair = true }).toolbar { settingsButton } }
            }
        }
        .sheet(isPresented: $showPair) { PairView() }
        // item-based, so the sheet always sees the payload that opened it.
        .sheet(item: $incomingPair) { payload in PairView(initial: payload) }
        .sheet(isPresented: $showSettings) { SettingsView(onPair: { showSettings = false; showPair = true }) }
        // A tapped notification lands on its conversation.
        .onChange(of: app.openChatId, initial: true) { _, _ in openPending() }
        .onChange(of: app.chatsVersion) { _, _ in openPending() }
        .onOpenURL { url in
            log.info("open url \(url.absoluteString.prefix(40), privacy: .public)")
            guard let payload = PairPayload.parse(url.absoluteString) else { log.error("pair link did not parse"); return }
            showSettings = false
            showPair = false
            incomingPair = payload
        }
    }
}

extension RootView {
    /// One column: the sidebar, and everything else pushed on top of it. The
    /// phone, and an iPad squeezed into a narrow Split View slot.
    @ViewBuilder
    private func stack(_ c: Connection) -> some View {
        NavigationStack(path: $path) {
            destinations(SidebarView(connection: c, path: $path), c)
                .toolbar { settingsButton }
        }
    }

    /// Two columns, as on the Mac: the sidebar stays put on the left, and what
    /// you open fills the right. The same `path` drives it — the sidebar
    /// appends, and the detail column is the stack that answers.
    @ViewBuilder
    private func split(_ c: Connection) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(connection: c, path: $path)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
                .toolbar { settingsButton }
        } detail: {
            NavigationStack(path: $path) {
                destinations(nothingOpen, c)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The right-hand column with nothing in it yet. The Mac shows an empty
    /// pane here too rather than picking a conversation for you.
    private var nothingOpen: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .superFont(30).foregroundStyle(Theme.textTertiary)
            Text("Pick a conversation").superFont(15, weight: .medium).foregroundStyle(Theme.textSecondary)
            Text("Or start one with + New chat.").superFont(13).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
    }

    /// Where a pushed value turns into a screen. Written once and applied to
    /// whichever view is the root of the stack, because that is the only thing
    /// that differs between the two shapes.
    @ViewBuilder
    private func destinations(_ view: some View, _ c: Connection) -> some View {
        view
            .navigationDestination(for: WireChat.self) { chat in
                ChatView(push: { path.append($0) },
                         connection: c, chat: chat, workspace: workspace(c, for: chat))
            }
            .navigationDestination(for: WorkspacePanel.self) { panel in
                switch panel.kind {
                case .files: FilesView(connection: c, workspace: panel.workspace)
                case .board: BoardView(connection: c, workspace: panel.workspace)
                case .routines: RoutinesView(connection: c, workspace: panel.workspace)
                case .chats: ChatsListView(connection: c, workspace: panel.workspace) { chat in path.append(chat) }
                }
            }
            .navigationDestination(for: FileRef.self) { ref in FileView(connection: c, ref: ref) }
            .navigationDestination(for: FolderRef.self) { ref in
                FilesView(connection: c, workspace: workspace(c, id: ref.workspaceId), folder: ref)
            }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
    }

    /// A project by id, with a stand-in if the tree hasn't named it yet.
    private func workspace(_ c: Connection, id: String) -> WireWorkspace {
        c.tree.flatMap(\.workspaces).first { $0.id == id }
            ?? WireWorkspace(id: id, name: "Project", path: "", kind: "app", status: .idle)
    }

    /// The project a chat belongs to; a stand-in row if the tree hasn't named it yet.
    private func workspace(_ c: Connection, for chat: WireChat) -> WireWorkspace {
        c.tree.flatMap(\.workspaces).first { $0.id == chat.workspaceId }
            ?? WireWorkspace(id: chat.workspaceId, name: chat.workspaceId == "__desktop_chat__" ? "Computer" : "Project",
                             path: "", kind: chat.workspaceId == "__desktop_chat__" ? "desktop" : "app", status: .idle)
    }

    /// Navigate to the chat a notification named, once its Mac has told us about it.
    private func openPending() {
        guard let chatId = app.openChatId, let machine = app.selected else { return }
        let c = app.connection(for: machine)
        guard let chat = c.chats.first(where: { $0.id == chatId }) else { return }
        path = NavigationPath()
        path.append(chat)
        app.openChatId = nil
    }
}

struct WelcomeView: View {
    var onPair: () -> Void

    var body: some View {
        // Centred by the spacers while it fits, scrolling once it doesn't —
        // otherwise the larger text sizes squeeze the copy until the headline
        // truncates rather than wrapping.
        GeometryReader { geo in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.panel)
        .navigationTitle("Superagent")
    }

    private var content: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.accent).frame(width: 84, height: 84)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accentFg).frame(width: 26, height: 26)
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            Text("Your Mac, in your pocket")
                .superFont(24, weight: .bold).foregroundStyle(Theme.textPrimary)
            Text("Follow the agent, send it work, approve what it asks — from anywhere. Pair once; no accounts, no setup.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 28)
            Spacer()
            Button(action: onPair) {
                Text("Pair a Mac")
                    .superFont(16, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Theme.accentFg)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            Text("On the Mac: Settings → Phone → Show pairing code")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 24)
        }
    }
}
