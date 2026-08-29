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
        List {
            if connection.state != .connected {
                ConnectionBanner(connection: connection).listRowBackground(Theme.card)
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchSection
            } else {
                computerRow
                browseSection
                ForEach(groups) { group in groupSection(group) }
                Section {
                    Button { newGroup() } label: {
                        Text("+ New group").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle(connection.machine.name)
        .toolbar { ToolbarItem(placement: .topBarLeading) { ConnectionPill(state: connection.state) } }
        .searchable(text: $query, prompt: "Search every conversation")
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

    // MARK: Sections

    private var computerRow: some View {
        Section {
            Button {
                if let c = computer { openProject(c) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").font(.system(size: 14)).foregroundStyle(Theme.textSecondary).frame(width: 22)
                    Text("Computer").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let c = computer { StatusIndicator(status: c.status) }
                }
            }
            .disabled(computer == nil)
            .listRowBackground(Theme.card)
        }
    }

    private var browseSection: some View {
        Section {
            ForEach(tabs) { ws in projectRows(ws) }
            if tabs.isEmpty {
                Button { newTab() } label: {
                    Text("Open a tab to browse").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.card)
            }
        } header: {
            groupHeader("Browse") { newTab() }
        }
    }

    private func groupSection(_ group: WireGroup) -> some View {
        Section {
            ForEach(group.workspaces) { ws in projectRows(ws) }
            if group.workspaces.isEmpty {
                Text("No projects yet — tap + to add a folder from the Mac.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .listRowBackground(Theme.card)
            }
        } header: {
            groupHeader(group.name) { addingTo = group }
                .contextMenu {
                    Button { groupName = group.name; renaming = group } label: { Label("Rename group", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await run { try await connection.deleteGroup(id: group.id) } } } label: { Label("Delete group", systemImage: "trash") }
                }
        }
    }

    private func groupHeader(_ title: String, add: @escaping () -> Void) -> some View {
        HStack {
            GroupLabel(text: title)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(connection.state != .connected)
            .accessibilityLabel("Add to \(title)")
        }
        .textCase(nil)
    }

    /// A project and, under it, the same tree the desktop shows.
    @ViewBuilder
    private func projectRows(_ ws: WireWorkspace) -> some View {
        let chats = connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
        let mine = routines.filter { $0.workspaceId == ws.id }
        let repos = ws.subrepos ?? []

        Button { openProject(ws) } label: { ProjectRow(workspace: ws, chats: chats) }
            .listRowBackground(Theme.card)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { removing = ws } label: { Label("Remove", systemImage: "xmark") }
            }

        // A folder of repos: collapsed by default, one line per repo, tap one
        // and it offers "Start session →" (opens that repo as its own project).
        if !repos.isEmpty {
            Button { toggle(ws.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: reposOpen.contains(ws.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary).frame(width: 12)
                    Text("\(repos.count) repo\(repos.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.leading, 40)
            }
            .listRowBackground(Theme.card)
            if reposOpen.contains(ws.id) {
                ForEach(repos) { r in
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Text(r.name).font(.system(size: 14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        if selectedRepo == r.path {
                            Button {
                                startSession(groupId: groupId(of: ws), repo: r)
                            } label: {
                                Text("Start session →").font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.accentFg)
                            }
                            .buttonStyle(.borderless)
                        } else if let b = r.branch, !b.isEmpty {
                            Text("⎇ \(b)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.leading, 52)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRepo = selectedRepo == r.path ? nil : r.path }
                    .listRowBackground(Theme.card)
                }
            }
        }

        // A project holds many conversations; show them only once there's a
        // choice to make, so a single-chat project stays as quiet as before.
        if chats.count > 1 {
            ForEach(chats) { chat in
                Button { path.append(chat) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Text(chat.title ?? "New chat").font(.system(size: 14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        if chat.live { ProgressView().controlSize(.mini) }
                    }
                    .padding(.leading, 40)
                }
                .listRowBackground(Theme.card)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { Task { await run { try await connection.deleteChat(chatId: chat.id) } } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }

        ForEach(mine) { r in
            NavigationLink(value: WorkspacePanel(kind: .routines, workspace: ws)) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 11)).foregroundStyle(r.isEnabled ? Theme.textSecondary : Theme.textTertiary)
                    Text(r.prompt).font(.system(size: 13)).foregroundStyle(r.isEnabled ? Theme.textPrimary : Theme.textTertiary).lineLimit(1)
                    Spacer()
                    if r.lastRunStatus == "running" { ProgressView().controlSize(.mini) }
                }
                .padding(.leading, 40)
            }
            .listRowBackground(Theme.card)
        }
    }

    private var searchSection: some View {
        Section {
            if hits.isEmpty {
                Text("No matches").foregroundStyle(Theme.textTertiary).listRowBackground(Theme.card)
            }
            ForEach(hits) { hit in
                Button { query = ""; app.openChatId = hit.chatId } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(hit.title ?? "New chat").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                            Text(Date(timeIntervalSince1970: hit.ts / 1000), format: .relative(presentation: .named))
                                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        Text(hit.snippet).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
                .listRowBackground(Theme.card)
            }
        } header: { GroupLabel(text: "\(hits.count) match\(hits.count == 1 ? "" : "es")").textCase(nil) }
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
