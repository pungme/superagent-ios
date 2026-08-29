import SwiftUI

/// The desktop sidebar, row for row (renderer/src/components/Sidebar.tsx):
/// Computer on top, the Browse tabs with their +, every project group with
/// its +, and under each project the collapsed repos tree, its conversations
/// (once there is more than one) and its routines. "+ New group" at the end.
/// Tapping a project opens the conversation it is on, like the desktop does.
struct SidebarView: View {
    let connection: Connection
    @Binding var path: NavigationPath
    @Environment(AppState.self) private var app

    @State private var routines: [WireRoutine] = []
    @State private var reposOpen: Set<String> = []
    @State private var selectedRepo: String?
    @State private var addingTo: WireGroup?
    @State private var renaming: WireGroup?
    @State private var groupName = ""
    @State private var removing: WireWorkspace?
    @State private var busy = false
    @State private var error: String?
    @State private var query = ""
    @State private var hits: [WireSearchHit] = []

    private static let tabsGroup = "__tabs"
    private var computer: WireWorkspace? { connection.tree.first { $0.id == "computer" }?.workspaces.first }
    private var tabs: [WireWorkspace] { connection.tree.first { $0.name == Self.tabsGroup }?.workspaces ?? [] }
    private var groups: [WireGroup] { connection.tree.filter { $0.id != "computer" && $0.name != Self.tabsGroup } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if connection.state != .connected {
                    ConnectionBanner(connection: connection)
                        .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 8)
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchSection
                } else {
                    computerRow
                    browseSection
                    ForEach(groups) { group in groupSection(group) }
                    // .sidebar-footer: "+ New group"
                    Button { newGroup() } label: {
                        Text("+ New group").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 20)
                }
            }
        }
        .background(Theme.panel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The status sits with the name; a toolbar item would be squeezed
            // into a glass circle on iOS 26.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(connection.machine.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(ConnectionPill.color(for: connection.state)).frame(width: 6, height: 6)
                        Text(ConnectionPill.label(for: connection.state)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search every conversation")
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            hits = (try? await connection.searchChats(q)) ?? []
        }
        .task(id: connection.state) { if connection.state == .connected { await loadRoutines() } }
        .refreshable { connection.connect(); await connection.refreshTree(); await loadRoutines() }
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

    /// .sidebar-dash-row — 12.5 semibold, secondary, monitor glyph; 6/10 padding.
    /// The Computer keeps several conversations too (DesktopChat.tsx): they nest
    /// under it exactly as a project's do.
    private var computerRow: some View {
        let chats = computer.map { c in connection.chats.filter { $0.workspaceId == c.id }.sorted { $0.updatedAt > $1.updatedAt } } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if let c = computer { openProject(c) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    Text("Computer").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let c = computer, c.status != .idle { StatusIndicator(status: c.status) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(computer == nil)
            if chats.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chats) { chat in
                        TreeRow {
                            Button { path.append(chat) } label: {
                                HStack(spacing: 7) {
                                    if chat.live { ProgressView().controlSize(.mini) }
                                    Text(chat.title ?? "New chat").lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { Task { await run { try await connection.deleteChat(chatId: chat.id) } } } label: { Label("Delete conversation", systemImage: "trash") }
                            }
                        }
                    }
                }
                .padding(.leading, 30).padding(.top, 1).padding(.bottom, 3)
                .background(alignment: .topLeading) {
                    Rectangle().fill(Theme.border).frame(width: 1).padding(.leading, 30 + 10).padding(.bottom, 8 + 3)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader("Browse", caret: false) { newTab() }
            ForEach(tabs) { ws in projectRows(ws) }
            if tabs.isEmpty {
                // .tabs-empty: the grey line is the control itself.
                Button { newTab() } label: {
                    Text("Open a tab to browse").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 10).padding(.top, 4).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }

    /// .sidebar-group: 6/6/6/4 padding, radius 10, 8 between groups.
    private func groupSection(_ group: WireGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(group.name, caret: true) { addingTo = group }
                .contextMenu {
                    Button { groupName = group.name; renaming = group } label: { Label("Rename group", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await run { try await connection.deleteGroup(id: group.id) } } } label: { Label("Delete group", systemImage: "trash") }
                }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.workspaces) { ws in projectRows(ws) }
            }
            .padding(.leading, 4)
            if group.workspaces.isEmpty {
                Button { addingTo = group } label: {
                    Text("Add a project…").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 10).padding(.top, 2).padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6).padding(.bottom, 6).padding(.leading, 4).padding(.trailing, 6)
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    /// .sidebar-group-header: caret, 11 pt uppercase 600 tracked 0.6, + at the right.
    private func groupHeader(_ title: String, caret: Bool, add: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            if caret {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary).frame(width: 16, height: 16)
            }
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(connection.state != .connected)
            .accessibilityLabel("Add to \(title)")
        }
        .padding(.leading, caret ? 3 : 6).padding(.trailing, 6).padding(.vertical, 2)
        .padding(.bottom, 3)
    }

    /// A project and, under it, the same tree the desktop shows.
    @ViewBuilder
    private func projectRows(_ ws: WireWorkspace) -> some View {
        let chats = connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
        let mine = routines.filter { $0.workspaceId == ws.id }
        let repos = ws.subrepos ?? []
        let showChats = chats.count > 1
        let hasTree = !repos.isEmpty || showChats || !mine.isEmpty

        // .sidebar-item: status dot, kind icon, 13.5/500 name, branch chip; 7/8 padding, radius 8.
        Button { openProject(ws) } label: {
            HStack(spacing: 8) {
                StatusIndicator(status: ws.status).frame(width: 10)
                ProjectGlyph(workspace: ws)
                Text(ws.isBrowser ? (ws.host ?? ws.name) : ws.name)
                    .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 6)
                if let b = ws.branch, !b.isEmpty {
                    Text("⎇ \(b)").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Theme.hover, in: Capsule()).lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
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
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary).frame(width: 10)
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
                                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                                    Text(r.name).lineLimit(1)
                                    Spacer()
                                    if selectedRepo == r.path {
                                        Button { startSession(groupId: groupId(of: ws), repo: r) } label: {
                                            Text("Start session →").font(.system(size: 11, weight: .semibold))
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.accentFg)
                                        }
                                        .buttonStyle(.borderless)
                                    } else if let b = r.branch, !b.isEmpty {
                                        Text("⎇ \(b)").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
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
                if showChats {
                    ForEach(chats) { chat in
                        TreeRow {
                            Button { path.append(chat) } label: {
                                HStack(spacing: 7) {
                                    if chat.live { ProgressView().controlSize(.mini) }
                                    Text(chat.title ?? "New chat").lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { Task { await run { try await connection.deleteChat(chatId: chat.id) } } } label: { Label("Delete conversation", systemImage: "trash") }
                            }
                        }
                    }
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
            .padding(.leading, 28).padding(.top, 1).padding(.bottom, 3)
            .background(alignment: .topLeading) {
                Rectangle().fill(Theme.border).frame(width: 1).padding(.leading, 28 + 10).padding(.bottom, 8 + 3)
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(hits.isEmpty ? "No matches" : "\(hits.count) match\(hits.count == 1 ? "" : "es")", caret: false) {}
            ForEach(hits) { hit in
                Button { query = ""; app.openChatId = hit.chatId } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(hit.title ?? "New chat").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                            Text(Date(timeIntervalSince1970: hit.ts / 1000), format: .relative(presentation: .named))
                                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        Text(hit.snippet).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Actions (the desktop's, one for one)

    /// setActive(ws.id): the project opens on the conversation it is on — the
    /// most recent one, or a fresh one when it has none yet.
    private func openProject(_ ws: WireWorkspace) {
        let chats = connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
        if let c = chats.first { path.append(c); return }
        Task {
            await run {
                let id = try await connection.createChat(workspaceId: ws.id)
                if let c = connection.chats.first(where: { $0.id == id }) { path.append(c) }
            }
        }
    }

    /// newTab(): a browser project in the tabs group, opened at once.
    private func newTab() {
        Task {
            await run {
                let id = try await connection.createBrowserTab()
                if let ws = connection.tree.flatMap(\.workspaces).first(where: { $0.id == id }) { openProject(ws) }
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
                if let ws = connection.tree.flatMap(\.workspaces).first(where: { $0.id == id }) { openProject(ws) }
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
struct WorkspacePanel: Hashable {
    enum Kind: Hashable { case files, board, routines }
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
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
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
            Rectangle().fill(Theme.border).frame(width: 8, height: 1).padding(.leading, 10)
            content()
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 3)
        }
        .frame(minHeight: 22)
    }
}

/// The kind glyph on a project row: folder, globe/favicon, or the Mac.
private struct ProjectGlyph: View {
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
        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        .frame(width: 16, height: 16)
    }
}
