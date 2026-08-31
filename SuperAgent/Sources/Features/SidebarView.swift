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
    @State private var busy = false
    @State private var error: String?
    @State private var query = ""
    @State private var hits: [WireSearchHit] = []
    /// Which way the sidebar is reading right now, remembered between launches.
    @AppStorage("sidebar.mode") private var modeRaw = SidebarMode.projects.rawValue
    private var mode: SidebarMode { SidebarMode(rawValue: modeRaw) ?? .projects }

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
            if connection.state != .connected {
                Section {
                    ConnectionBanner(connection: connection)
                        .listRowBackground(Theme.card)
                }
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchSection
            } else {
                modePicker
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
        .navigationTitle(connection.machine.name)
        .navigationBarTitleDisplayMode(.large)
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

    private func sheetsAndAlerts(_ view: some View) -> some View {
        view
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search every conversation")
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
                Task { await run { _ = try await connection.addWorkspace(groupId: group.id, name: dir.name, path: dir.path) } }
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
                if let c = computer { Task { await run { try await openProject(c) } } }
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
    private func branchRow(_ wt: WireWorktree, in ws: WireWorkspace) -> some View {
        let chat = wt.chatId.flatMap { id in connection.chats.first { $0.id == id } }
        TreeRow {
            Button {
                if let chat { path.append(chat) }
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
                        Task { await run { try await connection.deleteChat(chatId: chat.id) } }
                    } label: {
                        Label("Delete conversation", systemImage: "trash")
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
        Button { path.append(chat) } label: {
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
        .listRowBackground(Theme.card)
        .contextMenu {
            Button(role: .destructive) {
                Task { await run { try await connection.deleteChat(chatId: chat.id) } }
            } label: {
                Label("Delete conversation", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func chatTreeRow(_ chat: WireChat) -> some View {
        TreeRow {
            Button { path.append(chat) } label: {
                HStack(spacing: 7) {
                    if chat.live { ProgressView().controlSize(.mini) }
                    Text(chat.title ?? "New chat").lineLimit(1)
                    Spacer()
                    UnreadDot(on: connection.unread.isUnread(chat))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    Task { await run { try await connection.deleteChat(chatId: chat.id) } }
                } label: {
                    Label("Delete conversation", systemImage: "trash")
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
        Button { Task { await run { try await openProject(ws) } } } label: {
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
        .listRowBackground(Theme.card)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { removing = ws } label: { Label("Remove", systemImage: "xmark") }
        }
        .contextMenu {
            Button { Task { await run { try await openProject(ws) } } } label: { Label("Open", systemImage: "arrow.right") }
            Button(role: .destructive) { removing = ws } label: { Label("Remove project", systemImage: "xmark") }
        }

        // .routine-tree: one spine down the left, an elbow into every row.
        if hasTree {
            VStack(alignment: .leading, spacing: 0) {
                if !repos.isEmpty {
                    TreeRow {
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
                            TreeRow(depth: 2) {
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
                if let trees = worktrees[ws.id] {
                    // Only the extras. The folder's own conversation is the
                    // project row above; listing it here too drew the root as
                    // one more branch underneath itself.
                    ForEach(trees.filter { !$0.main }) { wt in branchRow(wt, in: ws) }
                    ForEach(chatsWithoutBranch(ws, trees: trees)) { chat in chatTreeRow(chat) }
                } else if showChats {
                    ForEach(chats) { chat in chatTreeRow(chat) }
                }
                ForEach(mine) { r in
                    TreeRow {
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
            // margin: 1px 0 3px; padding-left 20 (past the dot and the icon), spine at 10.
            .padding(.leading, 22).padding(.bottom, 4)
            .background(alignment: .topLeading) {
                Rectangle().fill(Theme.border).frame(width: 1).padding(.leading, 22 + 10).padding(.bottom, 21)
            }
            .listRowBackground(Theme.card)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
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
    private func openProject(_ ws: WireWorkspace) async throws {
        let chats = connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
        // The Mac says which copy of the project each chat is in, so this is
        // the same test the desktop makes on the project row: the chat whose
        // copy IS the folder. A chat on a branch has its own row underneath.
        if chats.contains(where: { $0.cwd != nil }) {
            if let root = chats.first(where: { $0.isFolderChat }) { path.append(root); return }
            path.append(WorkspacePanel(kind: .chats, workspace: ws))
            return
        }
        // A Mac too old to say. Ask which chat sits on the main worktree, and
        // failing that open the most recent one here — a guess, but never a
        // new conversation.
        let rows = ws.isBrowser || ws.isComputer
            ? []
            : ((try? await connection.worktrees(workspaceId: ws.id)) ?? [])
        if let id = rows.first(where: { $0.main })?.chatId,
           let root = chats.first(where: { $0.id == id }) {
            path.append(root)
            return
        }
        if let c = chats.first { path.append(c); return }
        // Nothing to open. Show the list, which is where "+ New chat" is.
        // Opening a project must never make a conversation by itself — a chat
        // appears when you ask for one, and nowhere else.
        path.append(WorkspacePanel(kind: .chats, workspace: ws))
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
                    path.append(c)
                    return
                }
                let chatId = try await connection.createChat(workspaceId: ws.id, root: true)
                if let c = connection.chats.first(where: { $0.id == chatId }) { path.append(c) }
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
                if let ws = connection.tree.flatMap(\.workspaces).first(where: { $0.id == id }) { try await openProject(ws) }
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
#if DEBUG
/// The sidebar with a Mac's worth of rows behind it and no Mac. Launch the app
/// with `-sidebarHarness` to look at both modes.
struct SidebarHarness: View {
    @State private var connection: Connection?
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) {
            if let c = connection { SidebarView(connection: c, path: $path) }
        }
        .task { if connection == nil { connection = Connection.sidebarHarness() } }
    }
}
#endif

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
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(depth - 1) * 14)
            Rectangle().fill(Theme.border).frame(width: 8, height: 1).padding(.leading, 10).padding(.top, 16)
            content()
                .superFont(13).foregroundStyle(Theme.textSecondary)
                .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 4)
        }
        .frame(minHeight: 34)
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
