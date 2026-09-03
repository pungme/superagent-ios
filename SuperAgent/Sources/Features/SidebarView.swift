import SwiftUI

/// The desktop sidebar, row for row (renderer/src/components/Sidebar.tsx):
/// Computer on top, the Browse tabs with their +, every project group with
/// its +, and under each project the collapsed repos tree, its conversations
/// (once there is more than one) and its routines. "+ New group" at the end.
/// Tapping a project opens the conversation it is on, like the desktop does.
struct SidebarView: View {
    /// The + target in a group header: 44 wide always, as tall as its glyph needs.
    @ScaledMetric(relativeTo: .subheadline) private var addTarget: CGFloat = 36

    let connection: Connection
    @Binding var path: NavigationPath
    /// How a conversation is shown. One column pushes it; two columns put it in
    /// the other column and leave this one alone — which is the difference
    /// between a sidebar and a stack, and why this is the caller's business.
    var open: (WireChat) -> Void
    /// The conversation on screen, so the row for it can say so. nil in one
    /// column, where the sidebar is not visible next to what it opened.
    var openId: String?
    /// A tab shows one way of reading the Mac and lets the tab bar do the
    /// switching; nil (the iPad) keeps the segmented picker and the memory.
    var fixedMode: SidebarMode? = nil
    /// The tabs have a Search tab of their own; the drawer search is the iPad's.
    var showsSearch = true
    @Environment(AppState.self) private var app

    @State private var routines: [WireRoutine] = []
    /// Every copy of each git project — the folder itself and the branches cut
    /// from it — keyed by project. The Mac's sidebar is a row per one of these,
    /// asked of git rather than of anything the app recorded.
    @State private var worktrees: [String: [WireWorktree]] = [:]
    @State private var reposOpen: Set<String> = []
    /// Collapsed groups, remembered on this phone (the caret is a real button
    /// here — on the desktop it's a 16 px glyph you can hit with a mouse).
    @AppStorage("sidebar.collapsedGroups") private var collapsedRaw = ""

    @State private var selectedRepo: String?
    @State private var addingTo: WireGroup?
    @State private var renaming: WireGroup?
    @State private var groupName = ""
    @State private var removing: WireWorkspace?
    /// The conversation a context menu asked to delete, held until confirmed.
    @State private var deletingChat: WireChat?
    @State private var busy = false
    @State private var error: String?
    @Environment(\.horizontalSizeClass) private var width
    @State private var query = ""
    @State private var hits: [WireSearchHit] = []
    /// Which way the sidebar is reading right now, remembered between launches.
    @AppStorage("sidebar.mode") private var modeRaw = SidebarMode.projects.rawValue
    private var mode: SidebarMode { fixedMode ?? SidebarMode(rawValue: modeRaw) ?? .projects }

    private static let tabsGroup = "__tabs"
    private var computer: WireWorkspace? { connection.tree.first { $0.id == "computer" }?.workspaces.first }
    private var tabs: [WireWorkspace] { connection.tree.first { $0.name == Self.tabsGroup }?.workspaces ?? [] }
    private var groups: [WireGroup] { connection.tree.filter { $0.id != "computer" && $0.name != Self.tabsGroup } }

    var body: some View {
        sheetsAndAlerts(listView)
    }

    /// The list and its chrome. Split from the modifiers below because as one
    /// expression this body took 704ms to type-check — the worst in the app by
    /// five times — and that limit is a time limit: a slower machine gives up
    /// where this one does not, which is exactly what Xcode Cloud kept doing.
    private var listView: some View {
        List {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchSection
            } else {
                if fixedMode == nil { modePicker }
                if mode == .activity {
                    activitySection
                } else {
                    machineSection
                    browseSection
                    ForEach(groups) { group in groupSection(group) }
                    newGroupSection
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.border)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        // Same treatment as the conversation: a status, not an obstruction. A
        // band across the top pushed every project down and drew the eye to the
        // one thing you cannot act on; floating it at the bottom keeps it
        // visible without taking the space the list is for. The chat hides its
        // own copy when the sidebar is on screen, so this one is not
        // conditional — on an iPad it is the only one left.
        .overlay(alignment: .bottom) {
            if connection.state != .connected {
                ConnectionFloat(connection: connection)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: connection.state == .connected)
        .navigationTitle(connection.machine.name)
        // A large title needs a phone's width to breathe; in an iPad's sidebar
        // column it truncates the Mac's name to make room for itself.
        .navigationBarTitleDisplayMode(width == .regular ? .inline : .large)
        .toolbar {
            // iOS 26 gives every toolbar item its own glass capsule and squeezes
            // it to a minimum width, which turned this pill into a white circle
            // with a single letter in it — "L" for Live. The pill draws its own
            // capsule already, so hide the system one and let it keep its width.
            // No sharedBackgroundVisibility here. It is an iOS 26 API, and
            // `if #available` does not help: availability guards the run, not
            // the compile — a symbol the build's SDK has never heard of still
            // has to resolve, and when one SwiftUI symbol fails to, the module
            // goes with it and the errors surface anywhere but here. The pill
            // draws its own capsule, so the system's shows through behind it
            // until this can come back.
            // The pill draws its own capsule, so the toolbar's would sit around
            // it as a halo. Hiding the system one needs an iOS 26 API, and the
            // SDK Xcode Cloud builds against does not have it — `if #available`
            // is no help there, since the symbol still has to resolve at
            // compile time. `#if compiler` is: on an older Xcode this is not
            // compiled at all, and the halo comes back until that Xcode catches
            // up. Nothing else changes.
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionPill(state: connection.state).fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionPill(state: connection.state).fixedSize()
                }
            }
            #else
            ToolbarItem(placement: .topBarLeading) {
                ConnectionPill(state: connection.state).fixedSize()
            }
            #endif
        }
    }

    @ViewBuilder
    private func searchableIfWanted(_ view: some View) -> some View {
        if showsSearch {
            view.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search every conversation")
        } else {
            view
        }
    }

    private func sheetsAndAlerts(_ view: some View) -> some View {
        searchableIfWanted(view)
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            hits = (try? await connection.searchChats(q)) ?? []
        }
        .task(id: connection.state) {
            guard connection.state == .connected else { return }
            await loadRoutines()
            await loadWorktrees()
        }
        .refreshable {
            connection.connect()
            await connection.refreshTree()
            await loadRoutines()
            await loadWorktrees()
        }
        .sheet(item: $addingTo) { group in
            FolderPickerView(connection: connection) { dir in
                Task {
                    await run {
                        let id = try await connection.addWorkspace(groupId: group.id, name: dir.name, path: dir.path)
                        try await startFirstChat(in: id)
                    }
                }
            }
        }
        .alert("Rename group", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $groupName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let g = renaming, !groupName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Task { await run { try await connection.renameGroup(id: g.id, name: groupName) } }
                }
                renaming = nil
            }
        }
        .alert("Delete \"\(deletingChat?.title ?? "New chat")\"?", isPresented: Binding(get: { deletingChat != nil }, set: { if !$0 { deletingChat = nil } })) {
            Button("Delete", role: .destructive) {
                if let chat = deletingChat { Task { await run { try await connection.deleteChat(chatId: chat.id) } } }
                deletingChat = nil
            }
            Button("Cancel", role: .cancel) { deletingChat = nil }
        } message: { Text("A conversation is work; this can't be undone.") }
        .confirmationDialog("Remove \(removing?.name ?? "this project")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let ws = removing { Task { await run { try await connection.removeWorkspace(id: ws.id) } } }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Its conversations go too. The folder on the Mac stays.") }
        .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    // MARK: Rows (Sidebar.tsx, main.css: .sidebar-dash-row, .sidebar-group-header, .sidebar-item, .routine-tree)

    /// Computer / Chats — the desktop's two non-project rows, at a tap size.
    private func dashRow(_ title: String, icon: String, status: WorkspaceStatus?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).superFont(15).foregroundStyle(Theme.textSecondary).frame(width: 22)
                Text(title).superFont(16, weight: .medium).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let status, status != .idle { StatusIndicator(status: status) }
                Image(systemName: "chevron.right").superFont(13, weight: .semibold).foregroundStyle(Theme.textTertiary.opacity(0.7))
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(computer == nil)
        .listRowBackground(Theme.card)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
    }

    /// A section header: the desktop's small caps, the caret and + as real buttons.
    /// Plain browser tabs, above the projects.
    @ViewBuilder
    private var browseSection: some View {
        Section {
            ForEach(tabs) { ws in projectRows(ws) }
            if tabs.isEmpty {
                Button { newTab() } label: {
                    Label("Open a tab to browse", systemImage: "plus")
                        .superFont(13.5)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
        } header: {
            sectionHeader("Browse", caret: false) { newTab() }
        }
    }

    @ViewBuilder
    private var newGroupSection: some View {
        Section {
            Button { newGroup() } label: {
                Label("New group", systemImage: "plus")
                    .superFont(13.5)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .listRowBackground(Theme.card)
        }
    }

    /// Computer and Chats: the two rows that are not projects.
    ///
    /// This file's `body` was 704ms to type-check, five times the next worst in
    /// the app, and that is what kept failing on Xcode Cloud: the limit is a
    /// time limit, so a slower machine gives up where this one does not. Each
    /// piece is named now so no single expression is large.
    @ViewBuilder
    private var machineSection: some View {
        Section {
            dashRow("Computer", icon: "desktopcomputer", status: computer?.status) {
                if let c = computer { openProject(c) }
            }
            dashRow("Chats", icon: "bubble.left", status: nil) {
                if let c = computer { path.append(WorkspacePanel(kind: .chats, workspace: c)) }
            }
        }
    }

    /// One project group. Extracted for the same reason as `groupMenu`: the
    /// List was a single expression the type checker would not finish, and it
    /// failed by blaming other files.
    @ViewBuilder
    private func groupSection(_ group: WireGroup) -> some View {
                Section {
                    if !collapsed.contains(group.id) {
                        ForEach(group.workspaces) { ws in projectRows(ws) }
                        if group.workspaces.isEmpty {
                            Button { addingTo = group } label: {
                                Label("Add a project…", systemImage: "plus")
                                    .superFont(13.5).foregroundStyle(Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.card)
                        }
                    }
                } header: {
                    sectionHeader(group.name, caret: true, collapsedKey: group.id) { addingTo = group }
                        .contextMenu { groupMenu(for: group) }
                }
    }

    /// Pulled out of the header's `.contextMenu` closure. Inline, with the two
    /// buttons and their async work, the whole `List` became one expression the
    /// type checker gave up on — and it gave up by inventing errors in other
    /// files, which is what Xcode Cloud kept reporting.
    @ViewBuilder
    private func groupMenu(for group: WireGroup) -> some View {
        Button {
            groupName = group.name
            renaming = group
        } label: {
            Label("Rename group", systemImage: "pencil")
        }
        Button(role: .destructive) {
            Task { await run { try await connection.deleteGroup(id: group.id) } }
        } label: {
            Label("Delete group", systemImage: "trash")
        }
    }

    private func sectionHeader(_ title: String, caret: Bool, collapsedKey: String? = nil, add: @escaping () -> Void) -> some View {
        let isCollapsed = collapsedKey.map(collapsed.contains) ?? false
        return HStack(spacing: 2) {
            Button {
                if let key = collapsedKey { toggleGroup(key) }
            } label: {
                HStack(spacing: 5) {
                    if caret {
                        Image(systemName: "chevron.right").superFont(10, weight: .bold)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .foregroundStyle(Theme.textTertiary).frame(width: 12)
                    }
                    Text(title).font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.5)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(collapsedKey == nil)
            Button(action: add) {
                Image(systemName: "plus").superFont(15, weight: .medium).foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: addTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(connection.state != .connected)
            .accessibilityLabel("Add to \(title)")
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 4))
    }

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: "\u{1}").map(String.init))
    }

    private func toggleGroup(_ id: String) {
        var next = collapsed
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        withAnimation(.easeOut(duration: 0.18)) { collapsedRaw = next.joined(separator: "\u{1}") }
    }

    /// Conversations with no branch of their own yet, and none of the copies
    /// git knows about. A chat waiting for its first message is one of these;
    /// so is one whose copy has been merged away.
    private func chatsWithoutBranch(_ ws: WireWorkspace, trees: [WireWorktree]) -> [WireChat] {
        let claimed = Set(trees.compactMap(\.chatId))
        return connection.chats
            .filter { $0.workspaceId == ws.id && !claimed.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// One branch of a project. The conversation is what you look for, so it
    /// reads first; the branch it runs in sits to the right. A row with no chat
    /// yet has nothing to put on the left, so the branch takes that place.
    @ViewBuilder
    private func branchRow(_ wt: WireWorktree, in ws: WireWorkspace, last: Bool = false) -> some View {
        let chat = wt.chatId.flatMap { id in connection.chats.first { $0.id == id } }
        return TreeRow(last: last) {
            Button {
                if let chat { open(chat) }
            } label: {
                HStack(spacing: 7) {
                    if chat?.live == true { ProgressView().controlSize(.mini) }
                    if let chat {
                        Text(chat.title ?? "New chat").lineLimit(1)
                    } else {
                        Text("⎇ " + wt.label).lineLimit(1).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    if chat != nil, let b = wt.branch, !b.isEmpty {
                        Text(wt.main ? b : "⎇ " + b)
                            .superFont(10.5)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    } else if chat == nil {
                        Text("no chat yet").superFont(10.5).foregroundStyle(Theme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(chat == nil)
            .contextMenu {
                if let chat {
                    Button(role: .destructive) {
                        deletingChat = chat
                    } label: {
                        Label(deleteLabel(chat), systemImage: "trash")
                    }
                }
            }
        }
        .id(wt.path)
    }

    /// Two ways of reading the same Mac. Projects is the desktop's sidebar,
    /// where a conversation is found by knowing where it lives. Activity is the
    /// one a phone actually wants: everything on this Mac in one flat list,
    /// most recent first, the way every messaging app you own is arranged.
    @ViewBuilder
    private var modePicker: some View {
        Picker("View", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
            ForEach(SidebarMode.allCases) { m in Text(m.label).tag(m) }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Theme.panel)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }

    /// Every conversation on this Mac, newest first — no groups, no projects,
    /// no branches. Where it lives is a subtitle here, not the structure.
    @ViewBuilder
    private var activitySection: some View {
        let names = projectNames
        let recent = connection.chats.sorted { $0.updatedAt > $1.updatedAt }
        Section {
            if recent.isEmpty {
                Text("Nothing here yet.").superFont(13).foregroundStyle(Theme.textTertiary)
                    .listRowBackground(Theme.card)
            }
            ForEach(recent) { chat in activityRow(chat, project: names[chat.workspaceId]) }
        }
    }

    private var projectNames: [String: String] {
        var out: [String: String] = [:]
        for ws in connection.tree.flatMap(\.workspaces) {
            out[ws.id] = ws.isBrowser ? (ws.host ?? ws.name) : ws.name
        }
        return out
    }

    /// One conversation, the way a message thread reads: who it is with (the
    /// project), what was last said, when, and whether you have read it.
    @ViewBuilder
    private func activityRow(_ chat: WireChat, project: String?) -> some View {
        Button { open(chat) } label: {
            HStack(alignment: .top, spacing: 8) {
                UnreadDot(on: connection.unread.isUnread(chat)).padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(chat.title ?? "New chat")
                            .superFont(14.5, weight: .medium)
                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                        if chat.live { ProgressView().controlSize(.mini) }
                        Spacer(minLength: 4)
                        Text(Date(timeIntervalSince1970: chat.updatedAt / 1000), format: .relative(presentation: .named))
                            .superFont(11).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    if let p = project, !p.isEmpty {
                        Text(p).superFont(11.5).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    if let preview = chat.preview, !preview.isEmpty {
                        Text(preview).superFont(12.5).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The row for the conversation on screen says so — with the sidebar
        // beside it, "which one am I in" is otherwise unanswerable.
        .listRowBackground(chat.id == openId ? Theme.hover : Theme.card)
        .contextMenu {
            Button(role: .destructive) {
                deletingChat = chat
            } label: {
                Label(deleteLabel(chat), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func chatTreeRow(_ chat: WireChat, last: Bool = false) -> some View {
        TreeRow(last: last) {
            Button { open(chat) } label: {
                HStack(spacing: 7) {
                    if chat.live { ProgressView().controlSize(.mini) }
                    Text(chat.title ?? "New chat")
                        .fontWeight(chat.id == openId ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    UnreadDot(on: connection.unread.isUnread(chat))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    deletingChat = chat
                } label: {
                    Label(deleteLabel(chat), systemImage: "trash")
                }
            }
        }
    }

    /// Ask the Mac which copies of each project exist. Cheap, and only for git
    /// projects: a browser tab or a plain folder has no branches to list.
    private func loadWorktrees() async {
        for ws in connection.tree.flatMap({ $0.workspaces }) where !ws.isBrowser && !ws.isComputer {
            if let rows = try? await connection.worktrees(workspaceId: ws.id), rows.count > 1 {
                worktrees[ws.id] = rows
            } else {
                worktrees[ws.id] = nil
            }
        }
    }

    /// A project and, under it, the same tree the desktop shows.
    @ViewBuilder
    private func projectRows(_ ws: WireWorkspace) -> some View {
        let chats = connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
        let mine = routines.filter { $0.workspaceId == ws.id }
        let repos = ws.subrepos ?? []
        let showChats = chats.count > 1
        // With no extras there is no list — the same rule the Mac follows.
        let extras: Int = {
            guard let trees = worktrees[ws.id] else { return showChats ? chats.count : 0 }
            return trees.filter { !$0.main }.count + chatsWithoutBranch(ws, trees: trees).count
        }()
        let hasTree = !repos.isEmpty || extras > 0 || !mine.isEmpty

        // .sidebar-item: status dot, kind icon, 13.5/500 name, branch chip; 7/8 padding, radius 8.
        Button { openProject(ws) } label: {
            HStack(spacing: 8) {
                StatusIndicator(status: ws.status).frame(width: 10)
                ProjectGlyph(workspace: ws)
                Text(ws.isBrowser ? (ws.host ?? ws.name) : ws.name)
                    .superFont(14.5, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 6)
                if let b = ws.branch, !b.isEmpty {
                    Text("⎇ \(b)").superFont(10).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Theme.hover, in: Capsule()).lineLimit(1)
                }
                // Shown on the project too: a project you have not expanded is
                // exactly where an unread reply would otherwise sit unseen.
                UnreadDot(on: connection.unread.any(in: chats))
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(chats.contains { $0.id == openId } ? Theme.hover : Theme.card)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { removing = ws } label: { Label("Remove", systemImage: "xmark") }
        }
        .contextMenu {
            Button { openProject(ws) } label: { Label("Open", systemImage: "arrow.right") }
            // Starting a conversation was reachable only by opening the project
            // and finding "+ New chat" inside it, so the menu you get by holding
            // a project offered no way to do the main thing you hold it for.
            Button { newChat(in: ws) } label: { Label("New chat", systemImage: "square.and.pencil") }
            Button(role: .destructive) { removing = ws } label: { Label("Remove project", systemImage: "xmark") }
        }

        // .routine-tree: one spine down the left, an elbow into every row.
        // Each row is a real List row — see TreeRow for why.
        if hasTree {
            // Whose elbow the spine stops at.
            let nonMain = (worktrees[ws.id] ?? []).filter { !$0.main }
            let loose: [WireChat] = {
                if let trees = worktrees[ws.id] { return chatsWithoutBranch(ws, trees: trees) }
                return showChats ? chats : []
            }()
            let treeEndsInRepos = mine.isEmpty && loose.isEmpty && nonMain.isEmpty
            Group {
                if !repos.isEmpty {
                    TreeRow(last: treeEndsInRepos && !reposOpen.contains(ws.id)) {
                        Button { toggle(ws.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: reposOpen.contains(ws.id) ? "chevron.down" : "chevron.right")
                                    .superFont(9, weight: .semibold).foregroundStyle(Theme.textTertiary).frame(width: 10)
                                Text("\(repos.count) repo\(repos.count == 1 ? "" : "s")")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if reposOpen.contains(ws.id) {
                        ForEach(repos) { r in
                            TreeRow(depth: 2, last: treeEndsInRepos && r.path == repos.last?.path) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right").superFont(10).foregroundStyle(Theme.textTertiary)
                                    Text(r.name).lineLimit(1)
                                    Spacer()
                                    if selectedRepo == r.path {
                                        Button { startSession(groupId: groupId(of: ws), repo: r) } label: {
                                            Text("Start session →").superFont(11, weight: .semibold)
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.accentFg)
                                        }
                                        .buttonStyle(.borderless)
                                    } else if let b = r.branch, !b.isEmpty {
                                        Text("⎇ \(b)").superFont(10.5).foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRepo = selectedRepo == r.path ? nil : r.path }
                            }
                        }
                    }
                }
                // A project holds many conversations; show them only once there's a
                // choice to make, so a single-chat project stays as quiet as before.
                // One row per branch, main first, the way the Mac lists them.
                // A branch is a copy of the project with a conversation in it;
                // a chat with no branch yet is just a conversation, and says so.
                if worktrees[ws.id] != nil {
                    // Only the extras. The folder's own conversation is the
                    // project row above; listing it here too drew the root as
                    // one more branch underneath itself.
                    ForEach(nonMain) { wt in
                        branchRow(wt, in: ws,
                                  last: mine.isEmpty && loose.isEmpty && wt.path == nonMain.last?.path)
                    }
                    ForEach(loose) { chat in
                        chatTreeRow(chat, last: mine.isEmpty && chat.id == loose.last?.id)
                    }
                } else if showChats {
                    ForEach(loose) { chat in
                        chatTreeRow(chat, last: mine.isEmpty && chat.id == loose.last?.id)
                    }
                }
                ForEach(mine) { r in
                    TreeRow(last: r.id == mine.last?.id) {
                        NavigationLink(value: WorkspacePanel(kind: .routines, workspace: ws)) {
                            HStack(spacing: 6) {
                                Circle().fill(r.lastRunStatus == "running" ? Theme.working : Theme.textTertiary).frame(width: 6, height: 6)
                                Text(r.prompt).lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(r.isEnabled ? 1 : 0.5)
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        Section {
            ForEach(hits) { hit in
                Button { query = ""; app.openChatId = hit.chatId } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(hit.title ?? "New chat").superFont(13.5, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                            Text(Date(timeIntervalSince1970: hit.ts / 1000), format: .relative(presentation: .named))
                                .superFont(11).foregroundStyle(Theme.textTertiary)
                        }
                        Text(hit.snippet).superFont(12).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
        }
    }

    // MARK: Actions (the desktop's, one for one)

    /// setActive(ws.id): the project opens on the conversation it is on — the
    /// most recent one, or a fresh one when it has none yet.
    /// Navigate into a project: its most recent chat, or a freshly created one
    /// if it has none. `async throws` so every caller composes it under ONE
    /// `run()` — this used to spawn its own `Task { await run { ... } } }`
    /// nested inside whatever `run()` the caller (startSession, newTab) was
    /// already inside. `run()`'s re-entrancy guard is one shared `busy` flag,
    /// so the inner call could see it still `true` from the outer one and
    /// silently do nothing — the first tap created the project but never
    /// created or opened a chat for it, with no error shown; a second tap
    /// (retrying "nothing happened") created a SECOND chat, which is what
    /// showed up as two sessions after a restart pulled a fresh chat list.
    /// The project row is the conversation in the folder itself — the Mac draws
    /// it that way, so tapping it opens that chat rather than whichever was
    /// touched last. The branches are the rows underneath.
    ///
    /// It opens; it does not create. Tapping a project to look at it used to
    /// leave a new empty conversation behind whenever the phone could not find
    /// one to open, which is every tap on a project whose chats had not arrived
    /// yet. A conversation appears when you tap "+ New chat" and at no other
    /// time.
    /// Nothing in here waits on the Mac. Opening a project used to ask it which
    /// copies of the project exist, inside `run`, which holds a lock for the
    /// whole sidebar — so on a phone whose socket was down, one tap on a folder
    /// swallowed every other tap for the thirty seconds it took that request to
    /// time out. It looked exactly like the app had frozen, and on an iPad,
    /// where the sidebar never goes away, it looked like it had frozen for good.
    private func openProject(_ ws: WireWorkspace) {
        let chats = connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
        // The Mac says which copy of the project each chat is in, so this is
        // the same test the desktop makes on the project row: the chat whose
        // copy IS the folder. A chat on a branch has its own row underneath.
        if chats.contains(where: { $0.cwd != nil }) {
            if let root = chats.first(where: { $0.isFolderChat }) { open(root); return }
            path.append(WorkspacePanel(kind: .chats, workspace: ws))
            return
        }
        // A Mac too old to say. Use the worktree list the sidebar already loaded
        // in the background — asking for a fresh one here is what froze it — and
        // failing that open the most recent conversation. A guess, but never a
        // new one, and never a wait.
        if let id = worktrees[ws.id]?.first(where: { $0.main })?.chatId,
           let root = chats.first(where: { $0.id == id }) {
            open(root)
            return
        }
        if let c = chats.first { open(c); return }
        // Nothing to open. Show the list, which is where "+ New chat" is.
        // Opening a project must never make a conversation by itself — a chat
        // appears when you ask for one, and nowhere else.
        path.append(WorkspacePanel(kind: .chats, workspace: ws))
    }

    /// The conversation a project you just added opens with.
    ///
    /// Opening a project you already have never makes one — looking at
    /// something should not leave a chat behind. But ADDING one is not looking,
    /// it is asking to work on it, and landing on an empty list with a
    /// "+ New chat" to press is a step nobody wanted.
    private func startFirstChat(in workspaceId: String) async throws {
        guard let ws = connection.tree.flatMap(\.workspaces).first(where: { $0.id == workspaceId })
        else { return }
        if let existing = connection.chats.first(where: { $0.workspaceId == workspaceId }) {
            open(existing)
            return
        }
        let chatId = try await connection.createChat(workspaceId: workspaceId, root: true)
        if let c = connection.chats.first(where: { $0.id == chatId }) { open(c) }
        else { openProject(ws) }
    }

    /// newTab(): a browser project in the tabs group, opened at once.
    private func newTab() {
        Task {
            await run {
                let id = try await connection.createBrowserTab()
                guard let ws = connection.tree.flatMap(\.workspaces).first(where: { $0.id == id }) else { return }
                // A new tab is asking for a conversation — it is the whole point
                // of the button — so this one makes it. Opening an existing
                // project never does.
                if let c = connection.chats.first(where: { $0.workspaceId == ws.id }) {
                    open(c)
                    return
                }
                let chatId = try await connection.createChat(workspaceId: ws.id, root: true)
                if let c = connection.chats.first(where: { $0.id == chatId }) { open(c) }
            }
        }
    }

    /// A conversation on this project, opened right away.
    ///
    /// Not `root: true`: the project row already opens the folder's own chat, so
    /// the thing this menu is for is a *second* conversation — which on the Mac
    /// is one that takes its own copy of the project.
    /// The conversation's name, in the menu that is covering its row.
    ///
    /// A context menu on iOS opens ON TOP of the thing it acts on, so the row
    /// you are deleting is the one you can no longer read. With several
    /// conversations under a project, "Delete conversation" could mean any of
    /// them. Clipped, because a menu as wide as a long title is its own problem.
    private func deleteLabel(_ chat: WireChat) -> String {
        let title = (chat.title ?? "New chat").trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = title.count > 32 ? title.prefix(32) + "\u{2026}" : Substring(title)
        return "Delete \u{201C}\(shown)\u{201D}"
    }

    private func newChat(in ws: WireWorkspace) {
        Task {
            await run {
                let chatId = try await connection.createChat(workspaceId: ws.id)
                if let c = connection.chats.first(where: { $0.id == chatId }) { open(c) }
            }
        }
    }

    private func newGroup() { Task { await run { try await connection.createGroup(name: "New group") } } }

    /// openFolderAsProject(groupId, name, path): focus if open, else add and open.
    private func startSession(groupId: String, repo: WireSubrepo) {
        selectedRepo = nil
        Task {
            await run {
                let id = try await connection.addWorkspace(groupId: groupId, name: repo.name, path: repo.path)
                try await startFirstChat(in: id)
            }
        }
    }

    private func groupId(of ws: WireWorkspace) -> String {
        connection.tree.first { $0.workspaces.contains { $0.id == ws.id } }?.id ?? groups.first?.id ?? ""
    }

    private func toggle(_ id: String) {
        if reposOpen.contains(id) { reposOpen.remove(id) } else { reposOpen.insert(id) }
    }

    private func loadRoutines() async {
        routines = (try? await connection.listRoutines()) ?? []
    }

    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await work(); Haptics.tap() } catch { self.error = error.localizedDescription; Haptics.warning() }
    }
}

/// Files / Todo / Routines behind a project, pushed from its bar.
/// Which way the sidebar is reading the Mac.
enum SidebarMode: String, CaseIterable, Identifiable {
    case activity, projects
    var id: String { rawValue }
    var label: String { self == .activity ? "Activity" : "Projects" }
}

/// Something happened here that you have not read. The Mac draws the same dot,
/// in the same place, for the same reason.
struct UnreadDot: View {
    let on: Bool
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0)
            .accessibilityLabel(on ? "Unread" : "")
    }
}

struct WorkspacePanel: Hashable {
    enum Kind: Hashable { case files, board, routines, chats }
    let kind: Kind
    let workspace: WireWorkspace
}

/// Pick a folder on the Mac, the way the desktop's "+" opens a folder dialog.
struct FolderPickerView: View {
    let connection: Connection
    let pick: (WireDir) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var current: String?
    @State private var dirs: [WireDir] = []
    @State private var crumbs: [String] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Reading the Mac…").foregroundStyle(.secondary) }
                }
                if let cur = current, !loading {
                    Section {
                        Button {
                            pick(WireDir(name: (cur as NSString).lastPathComponent, path: cur, repo: false)); dismiss()
                        } label: { Label("Use this folder", systemImage: "checkmark.circle") }
                    } header: { Text(cur.replacingOccurrences(of: NSHomeDirectory(), with: "~")).textCase(nil) }
                }
                ForEach(dirs) { d in
                    Button { Task { await load(d.path) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: d.repo ? "chevron.left.forwardslash.chevron.right" : "folder.fill")
                                .foregroundStyle(d.repo ? Theme.textSecondary : Theme.needsYou).frame(width: 20)
                            Text(d.name).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").superFont(12, weight: .semibold).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Add a project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if crumbs.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { Task { crumbs.removeLast(); await load(crumbs.last, push: false) } } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Up one folder")
                    }
                }
            }
            .task { await load(nil) }
            .alert("Couldn't read that folder", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func load(_ path: String?, push: Bool = true) async {
        loading = true
        defer { loading = false }
        do {
            let r = try await connection.listDirs(path: path)
            current = r.path
            dirs = r.dirs
            if push { crumbs.append(r.path) }
        } catch { self.error = error.localizedDescription }
    }
}

/// .routine-tree-row: 11.5 pt, secondary, 3/8/3/10 padding, radius 6; the
/// elbow (8 px, at mid-height) meets the spine the parent draws.
private struct TreeRow<Content: View>: View {
    var depth: Int = 1
    /// The tree ends here: the spine drops to this row's elbow and stops.
    var last: Bool = false
    @ViewBuilder let content: () -> Content

    /// Each of these is its own List row. The tree used to be one row holding
    /// them all in a VStack, which read fine but meant the row's single
    /// context-menu interaction was shared: holding any conversation lifted
    /// the whole block, and the menu could belong to a different row than the
    /// one under your finger. One row each gives every conversation its own
    /// menu and its own lift; the spine is drawn per-row so it still connects.
    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(depth - 1) * 14)
            Rectangle().fill(Theme.border).frame(width: 8, height: 1).padding(.leading, 10)
            content()
                .superFont(13).foregroundStyle(Theme.textSecondary)
                .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 4)
        }
        .frame(minHeight: 34)
        .listRowInsets(EdgeInsets(top: 0, leading: 38, bottom: 0, trailing: 8))
        .listRowSeparator(.hidden)
        // The background receives the List cell's full height; the content
        // view above does not. Drawing the rail there left a gap around every
        // separator. One rail per nesting level also keeps repo children
        // connected to both their parent and their own elbow.
        .listRowBackground(
            ZStack(alignment: .topLeading) {
                Theme.card
                ForEach(0..<depth, id: \.self) { level in
                    Rectangle().fill(Theme.border)
                        .frame(width: 1)
                        .frame(maxHeight: level == depth - 1 && last ? 17 : .infinity,
                               alignment: .top)
                        .padding(.leading, 48 + CGFloat(level) * 14)
                }
            }
        )
    }
}

/// The kind glyph on a project row: folder, globe/favicon, or the Mac.
private struct ProjectGlyph: View {
    @ScaledMetric(relativeTo: .footnote) private var box: CGFloat = 16

    let workspace: WireWorkspace
    var body: some View {
        Group {
            if workspace.isBrowser, let host = workspace.host, let url = URL(string: "https://\(host)/favicon.ico") {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFit() } else { Image(systemName: "globe") }
                }
            } else if workspace.isBrowser {
                Image(systemName: "globe")
            } else if workspace.isComputer {
                Image(systemName: "desktopcomputer")
            } else {
                Image(systemName: "folder")
            }
        }
        .superFont(13).foregroundStyle(Theme.textSecondary)
        .frame(width: box, height: box)
    }
}
