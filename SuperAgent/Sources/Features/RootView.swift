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
    /// The bottom bar, on a phone. Each tab keeps its own stack, the way every
    /// tabbed app does: switching away and back should find things where you
    /// left them, not where another tab went.
    private enum AppTab: String { case projects, activity, chat, search, settings }
    @State private var tab: AppTab = {
        // `-tab chat` opens on that tab: a layout you cannot reach is a layout
        // you cannot check, and the simulator's touch injection is not a way
        // to reach one (see -openChat).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count,
           let wanted = AppTab(rawValue: args[i + 1]) { return wanted }
        return .projects
    }()
    @State private var projectsPath = NavigationPath()
    @State private var activityPath = NavigationPath()
    @State private var chatPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    /// An iPad, or an iPhone in landscape that is wide enough to hold two
    /// columns. The Mac's window is a sidebar and the thing you are working on;
    /// with the room to do the same, do the same.
    @Environment(\.horizontalSizeClass) private var width
    @State private var columns = NavigationSplitViewVisibility.all
    /// The conversation the second column is showing.
    ///
    /// Two columns select; they do not push. Appending to the detail stack put
    /// a second copy of the conversation on top of the first every time you
    /// tapped its project, gave it a Back button that went to an empty pane,
    /// and left the sidebar unable to say which one you were in — a sidebar you
    /// can see is a selection, not a history.
    @State private var shown: WireChat?
    /// The conversation most recently on screen, in either shape. A foldable
    /// changes shape mid-conversation: unfolded it is two columns, folded a
    /// phone. Without this the chat you were reading was simply gone after a
    /// fold, with the sidebar in its place.
    @State private var lastOpened: WireChat?
    /// ⌘K's palette (CommandPalette): the Mac's way of going anywhere.
    @State private var showPalette = false
    /// Split view (iPad): the conversations side by side in the second column,
    /// two to four of them, or empty for one conversation as before.
    @State private var tiles: [WireChat] = []
    /// The window of the split your typing goes to.
    @State private var focusedTile = 0
    /// The split comes back after a relaunch, by its conversations' ids.
    @AppStorage("splitTileIds") private var savedTileIds = ""

    var body: some View {
        Group {
            if let machine = app.selected {
                let c = app.connection(for: machine)
                if width == .regular { split(c) } else { tabs(c) }
            } else {
                NavigationStack { WelcomeView(onPair: { showPair = true }).toolbar { settingsButton } }
            }
        }
        // ⌘K, from anywhere in the app, as on the Mac. A button the eye never
        // sees but the keyboard does: it is also what holding ⌘ on an iPad
        // lists, so the shortcut can be found without being told.
        .background {
            if app.selected != nil {
                Button("Go to…") {
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { showPalette.toggle() }
                }
                    .keyboardShortcut("k", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        // A phone gets a sheet. An iPad gets a card over the window, there
        // and gone with no animation — the sheet's slide up and down was the
        // slowest thing about going somewhere with ⌘K.
        .sheet(isPresented: Binding(get: { showPalette && width != .regular },
                                    set: { if !$0 { showPalette = false } })) {
            palette
        }
        .overlay {
            if showPalette, width == .regular {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18).ignoresSafeArea()
                        .onTapGesture { showPalette = false }
                    palette
                        .frame(width: 600, height: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
                        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
                        .padding(.top, 90)
                }
                // Where it was asked for, not where a keyboard would shove it.
                .ignoresSafeArea(.keyboard)
                .transition(.identity)
            }
        }
        .animation(nil, value: showPalette)
        // -palette: open on it, for a test to look at.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-palette") { showPalette = true }
        }
        .sheet(isPresented: $showPair) { PairView() }
        // item-based, so the sheet always sees the payload that opened it.
        .sheet(item: $incomingPair) { payload in PairView(initial: payload) }
        .sheet(isPresented: $showSettings) { SettingsView(onPair: { showSettings = false; showPair = true }) }
        // A tapped notification lands on its conversation.
        .onChange(of: app.openChatId, initial: true) { _, _ in openPending() }
        .onChange(of: app.chatsVersion) { _, _ in openPending() }
        // Folded or unfolded, turned or split: the conversation comes along.
        .onChange(of: width) { was, now in carryOver(from: was, to: now) }
        // Another Mac: what was open belonged to the old one's projects.
        .onChange(of: app.machineSwitches) { _, _ in
            projectsPath = NavigationPath()
            activityPath = NavigationPath()
            chatPath = NavigationPath()
            searchPath = NavigationPath()
            path = NavigationPath()
            shown = nil
            lastOpened = nil
        }
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
    /// The phone: a bottom bar. Projects and Activity are the two ways of
    /// reading the Mac that used to share a segmented picker; Chat is the
    /// Computer's conversation; Search gets the trailing slot the system
    /// reserves for it; Settings stops being a gear floating over the title.
    @ViewBuilder
    private func tabs(_ c: Connection) -> some View {
        TabView(selection: $tab) {
            Tab("Projects", systemImage: "folder", value: AppTab.projects) {
                NavigationStack(path: $projectsPath) {
                    destinations(
                        SidebarView(connection: c, path: $projectsPath,
                                    open: { projectsPath.append($0) }, openId: nil,
                                    fixedMode: .projects, showsSearch: false),
                        c, $projectsPath
                    )
                }
            }
            Tab("Activity", systemImage: "clock", value: AppTab.activity) {
                NavigationStack(path: $activityPath) {
                    destinations(
                        SidebarView(connection: c, path: $activityPath,
                                    open: { activityPath.append($0) }, openId: nil,
                                    fixedMode: .activity, showsSearch: false),
                        c, $activityPath
                    )
                }
            }
            Tab("Chat", systemImage: "bubble.left", value: AppTab.chat) {
                NavigationStack(path: $chatPath) {
                    destinations(ComputerChatsTab(connection: c, path: $chatPath), c, $chatPath)
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    destinations(SearchTabView(connection: c, path: $searchPath), c, $searchPath)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(showsDone: false, onPair: { showPair = true })
            }
        }
    }

    /// Two columns, as on the Mac: the sidebar stays put on the left, and what
    /// you open fills the right. The same `path` drives it — the sidebar
    /// appends, and the detail column is the stack that answers.
    @ViewBuilder
    private func split(_ c: Connection) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(
                connection: c,
                path: $path,
                // Selecting, not pushing: the conversation becomes the second
                // column's root, and anything already stacked on it goes.
                open: { chat in
                    // In the split: go to its window. Anything else leaves the
                    // split — it waits to be opened beside again — as on the Mac.
                    if let i = tiles.firstIndex(where: { $0.id == chat.id }) {
                        focusedTile = i
                        return
                    }
                    setTiles([])
                    path = NavigationPath()
                    shown = chat
                },
                openId: tiles.indices.contains(focusedTile) ? tiles[focusedTile].id : shown?.id,
                asSidebar: true,
                openBeside: { chat in openBeside(chat) },
                openSplit: { chats in
                    guard chats.count >= 2 else { return }
                    path = NavigationPath()
                    setTiles(Array(chats.prefix(IPadSplit.max)))
                    focusedTile = 0
                }
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            .toolbar { settingsButton }
        } detail: {
            Group {
                if tiles.count >= 2 {
                    splitDetail(c)
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    NavigationStack(path: $path) {
                        destinations(detail(c), c, $path)
                    }
                }
            }
            // Drag a conversation from the sidebar onto this column: beside.
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, let chat = c.chats.first(where: { $0.id == id }) else { return false }
                return openBeside(chat)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: app.chatsVersion) { _, _ in restoreTiles(c) }
        .onAppear { restoreTiles(c) }
    }

    /// Put a conversation in a window beside the one on screen. False when four are open.
    @discardableResult
    private func openBeside(_ chat: WireChat) -> Bool {
        if let i = tiles.firstIndex(where: { $0.id == chat.id }) { focusedTile = i; return true }
        var next = tiles
        if next.isEmpty {
            guard let current = shown, current.id != chat.id else { shown = chat; return true }
            next = [current]
        }
        guard next.count < IPadSplit.max else { Haptics.warning(); return false }
        next.append(chat)
        setTiles(next)
        focusedTile = next.count - 1
        Haptics.tap()
        return true
    }

    private func setTiles(_ next: [WireChat]) {
        tiles = next
        savedTileIds = next.count >= 2 ? next.map(\.id).joined(separator: ",") : ""
        if focusedTile >= next.count { focusedTile = max(0, next.count - 1) }
    }

    /// Bring the split back once the conversations it names are known.
    private func restoreTiles(_ c: Connection) {
        // `-split c1,c2`: open on a split of those conversations, for a test to look at.
        let args = ProcessInfo.processInfo.arguments
        let wanted = args.firstIndex(of: "-split").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let ids = wanted ?? savedTileIds
        guard tiles.isEmpty, !ids.isEmpty else { return }
        let found = ids.split(separator: ",").compactMap { id in c.chats.first { $0.id == String(id) } }
        if found.count >= 2 { tiles = found; shown = found[0] }
    }

    /// Take window i off screen (its conversation keeps going on the Mac).
    private func closeTile(_ i: Int) {
        guard tiles.indices.contains(i) else { return }
        var next = tiles
        next.remove(at: i)
        if next.count < 2 {
            shown = next.first
            setTiles([])
        } else {
            setTiles(next)
            focusedTile = min(focusedTile, next.count - 1)
        }
    }

    /// The second column as a split: each window a whole conversation with its
    /// own bar (number, title, project) and its own stack.
    @ViewBuilder
    private func splitDetail(_ c: Connection) -> some View {
        GeometryReader { geo in
            let rows = IPadSplit.rows(tiles.count, width: geo.size.width)
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(rows[r], id: \.self) { i in
                            if tiles.indices.contains(i) { tileView(c, i) }
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Theme.panel)
        // ⌘1–4 with a keyboard: go to that window.
        .background {
            ForEach(0..<min(tiles.count, IPadSplit.max), id: \.self) { i in
                Button("Window \(i + 1)") { focusedTile = i }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func tileView(_ c: Connection, _ i: Int) -> some View {
        let chat = tiles[i]
        let focused = i == focusedTile
        let ws = workspace(c, for: chat)
        let title = c.chats.first { $0.id == chat.id }?.title ?? chat.title ?? "New chat"
        VStack(spacing: 0) {
            // The window's own header: its number, the session's name as the
            // headline, the project small beside it, and a way off screen.
            HStack(spacing: 8) {
                TileNumber(index: i, focused: focused)
                Text(title).superFont(14, weight: .semibold)
                    .foregroundStyle(focused ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(ws.isBrowser ? (ws.host ?? ws.name) : ws.name)
                    .superFont(12).foregroundStyle(Theme.textTertiary).lineLimit(1)
                Spacer(minLength: 4)
                Button { closeTile(i) } label: {
                    Image(systemName: "xmark").superFont(12, weight: .semibold)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take this window off screen")
            }
            .padding(.leading, 12).padding(.trailing, 6)
            .frame(height: 40)
            .background(Theme.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
            TileStack { tilePath in
                destinations(
                    ChatView(push: { tilePath.wrappedValue.append($0) }, openPanel: { tilePath.wrappedValue.append($0) },
                             connection: c, chat: chat, workspace: ws)
                        // The header above says whose window it is; a second
                        // bar inside would merge into the column's own.
                        .toolbar(.hidden, for: .navigationBar)
                        .id(chat.id),
                    c, tilePath)
            }
            .environment(\.compactComposer, true)
            .environment(\.inSplitTile, true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? Theme.textTertiary : Theme.border, lineWidth: focused ? 1.2 : 0.8)
        )
        .simultaneousGesture(TapGesture().onEnded { focusedTile = i })
        .id(chat.id)
    }

    /// The second column: the conversation you picked, at the root of its own
    /// stack — so Files, the board and a file open on top of it with a Back
    /// that returns to the conversation, and the conversation itself has no
    /// Back at all, because there is nothing behind it.
    @ViewBuilder
    private func detail(_ c: Connection) -> some View {
        if let chat = shown {
            ChatView(push: { path.append($0) }, openPanel: { path.append($0) },
                     connection: c, chat: chat, workspace: workspace(c, for: chat))
                .onAppear { lastOpened = chat }
                // A different conversation is a different screen, not the same
                // one with new contents.
                .id(chat.id)
        } else {
            nothingOpen
        }
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
    private func destinations(_ view: some View, _ c: Connection, _ path: Binding<NavigationPath>) -> some View {
        view
            .navigationDestination(for: WireChat.self) { chat in
                ChatView(push: { path.wrappedValue.append($0) }, openPanel: { path.wrappedValue.append($0) },
                         connection: c, chat: chat, workspace: workspace(c, for: chat))
                    .onAppear { lastOpened = chat }
                    // The tabs choose a place to go; once a conversation is
                    // open it owns the whole phone, just like the desktop's
                    // session pane. Back returns to the list and its bar.
                    .toolbar(.hidden, for: .tabBar)
                    // A different conversation is a different screen. Replacing
                    // the top of the stack with another chat — which is what
                    // "New chat" does from inside one — reused the same view
                    // otherwise: onAppear never ran again, so it never
                    // subscribed to the new conversation or rebuilt its
                    // transcript, and the button looked like it did nothing.
                    .id(chat.id)
            }
            .navigationDestination(for: WorkspacePanel.self) { panel in
                switch panel.kind {
                case .files: FilesView(connection: c, workspace: panel.workspace)
                case .board: BoardView(connection: c, workspace: panel.workspace)
                case .routines: RoutinesView(connection: c, workspace: panel.workspace)
                case .chats: ChatsListView(connection: c, workspace: panel.workspace) { chat in path.wrappedValue.append(chat) }
                }
            }
            .navigationDestination(for: SplitRoute.self) { route in
                SplitGridView(connection: c, splitId: route.id) { chat in path.wrappedValue.append(chat) }
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
            ?? WireWorkspace(id: chat.workspaceId, name: chat.workspaceId == "__desktop_chat__" ? "Chats" : "Project",
                             path: "", kind: chat.workspaceId == "__desktop_chat__" ? "desktop" : "app", status: .idle)
    }

    /// The shape changed under an open conversation: put it where the new
    /// shape keeps one. To the phone shape, it goes on the Projects tab's
    /// stack; to two columns, it becomes the second column. A conversation
    /// already left (Back pressed on the phone) is not brought back.
    private func carryOver(from was: UserInterfaceSizeClass?, to now: UserInterfaceSizeClass?) {
        guard was != nil, was != now else { return }
        if now == .regular {
            let somethingOpen = [projectsPath, activityPath, chatPath, searchPath].contains { !$0.isEmpty }
            guard somethingOpen, let chat = lastOpened else { return }
            projectsPath = NavigationPath()
            activityPath = NavigationPath()
            chatPath = NavigationPath()
            searchPath = NavigationPath()
            path = NavigationPath()
            shown = chat
        } else if let chat = shown {
            tab = .projects
            projectsPath = NavigationPath()
            projectsPath.append(chat)
            path = NavigationPath()
        }
    }

    /// ⌘K's palette for the paired Mac.
    @ViewBuilder
    private var palette: some View {
        if let machine = app.selected {
            let c = app.connection(for: machine)
            CommandPalette(
                connection: c,
                current: (shown ?? lastOpened).map { workspace(c, for: $0) },
                openChat: { go(to: $0) },
                openProject: { ws in openProject(ws, c) },
                newChat: { ws in startChat(in: ws, c) },
                openSettings: { showSettings = true },
                close: { showPalette = false })
        }
    }

    /// Put a conversation on screen, in whichever shape the app is in.
    private func go(to chat: WireChat) {
        if width == .regular {
            path = NavigationPath()
            shown = chat
        } else {
            tab = .projects
            projectsPath = NavigationPath()
            projectsPath.append(chat)
        }
    }

    /// A project from ⌘K: its most recent conversation, or a new one if it has none.
    private func openProject(_ ws: WireWorkspace, _ c: Connection) {
        if let latest = c.chats.filter({ $0.workspaceId == ws.id }).max(by: { $0.updatedAt < $1.updatedAt }) {
            go(to: latest)
        } else {
            startChat(in: ws, c)
        }
    }

    private func startChat(in ws: WireWorkspace, _ c: Connection) {
        Task {
            guard let id = try? await c.createChat(workspaceId: ws.id),
                  let chat = c.chats.first(where: { $0.id == id }) else { return }
            go(to: chat)
        }
    }

    /// Navigate to the chat a notification named, once its Mac has told us about it.
    private func openPending() {
        guard let chatId = app.openChatId, let machine = app.selected else { return }
        let c = app.connection(for: machine)
        guard let chat = c.chats.first(where: { $0.id == chatId }) else { return }
        if width == .regular {
            path = NavigationPath()
            shown = chat
        } else {
            tab = .activity
            activityPath = NavigationPath()
            // A beat later, not in the same update: pushed while the tab bar was
            // still being set up (a notification opening the app), the chat's
            // "hide the tab bar" was lost, and the bar sat beside or under the
            // conversation — down the whole side of an iPhone Duo's cover screen.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                activityPath.append(chat)
            }
        }
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
