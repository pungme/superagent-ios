import SwiftUI

/// ⌘K, as on the Mac: type to go anywhere.
///
/// The Mac's palette jumps to a conversation or a project, or runs an action,
/// from one field. An iPad with a keyboard is the same kind of machine to work
/// at, and it had no shortcut at all: everything was a reach for the screen.
/// Arrows move the selection, Return opens it, Esc closes.
struct CommandPalette: View {
    let connection: Connection
    /// The project you are in, for "New chat" to start one there.
    let current: WireWorkspace?
    let openChat: (WireChat) -> Void
    let openProject: (WireWorkspace) -> Void
    let newChat: (WireWorkspace) -> Void
    let openSettings: () -> Void
    /// Put the palette away: a sheet on a phone, a card over the window on an
    /// iPad, so whoever shows it says how it goes.
    let close: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        let items = CommandPaletteModel.items(
            query: query,
            chats: connection.chats,
            workspaces: connection.tree.flatMap(\.workspaces),
            current: current
        )
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                TextField("Go to a chat or project, or run an action", text: $query)
                    .superFont(16)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.go)
                    .accessibilityIdentifier("palette-field")
                    .onSubmit { run(items, at: selected) }
                    .onKeyPress(.downArrow) { move(+1, count: items.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: items.count); return .handled }
                    .onKeyPress(.escape) { closeNow(); return .handled }
                Text("esc").superFont(11, weight: .medium).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if items.isEmpty {
                            Text("Nothing matches “\(query)”")
                                .superFont(13).foregroundStyle(Theme.textTertiary)
                                .padding(16)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || items[index - 1].section != item.section {
                                SmallCapsHeader(title: item.section.rawValue)
                                    .padding(.horizontal, 16)
                            }
                            row(item, selected: index == selected)
                                .id(item.id)
                                .onTapGesture { run(items, at: index) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: selected) { _, now in
                    guard items.indices.contains(now) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { scroller.scrollTo(items[now].id) }
                }
            }
        }
        .background(Theme.panel)
        .onAppear { focused = true }
        // A new query is a new list: start from its top.
        .onChange(of: query) { _, _ in selected = 0 }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func row(_ item: CommandPaletteModel.Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let ws = item.workspace {
                    ProjectGlyph(connection: connection, workspace: ws)
                } else {
                    Image(systemName: item.systemImage).superFont(14).foregroundStyle(Theme.textSecondary)
                        .frame(width: 19, height: 19)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).superFont(14, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let sub = item.subtitle {
                    Text(sub).superFont(12).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return").superFont(11).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selected ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("palette-row")
    }

    /// Gone at once: no animation on the way out either.
    private func closeNow() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { close() }
    }

    private func move(_ by: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + by + count) % count
    }

    private func run(_ items: [CommandPaletteModel.Item], at index: Int) {
        guard items.indices.contains(index) else { return }
        let action = items[index].action
        closeNow()
        switch action {
        case let .chat(chat): openChat(chat)
        case let .project(ws): openProject(ws)
        case let .newChat(ws): newChat(ws)
        case .settings: openSettings()
        }
    }
}

/// What the palette lists for a query. Kept apart from the view so it can be
/// tested without one.
enum CommandPaletteModel {
    enum Section: String { case actions = "Actions", recent = "Recent", chats = "Chats", projects = "Projects" }

    enum Action {
        case chat(WireChat)
        case project(WireWorkspace)
        case newChat(WireWorkspace)
        case settings
    }

    struct Item: Identifiable {
        let id: String
        let section: Section
        let title: String
        let subtitle: String?
        let systemImage: String
        let workspace: WireWorkspace?
        let action: Action
    }

    /// Every word of the query somewhere in the text, in any order — how the
    /// Mac's palette matches, so "wepush e2e" finds "e2e test (wepush)".
    static func matches(_ query: String, _ text: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        let hay = text.lowercased()
        return words.allSatisfy { hay.contains($0) }
    }

    static func items(
        query raw: String,
        chats: [WireChat],
        workspaces: [WireWorkspace],
        current: WireWorkspace?
    ) -> [Item] {
        let query = raw.trimmingCharacters(in: .whitespaces)
        let byId = Dictionary(workspaces.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let name = { (id: String) -> String in
            id == "__desktop_chat__" ? "Computer" : (byId[id]?.name ?? "")
        }
        func chatItem(_ c: WireChat, _ section: Section) -> Item {
            Item(id: "chat:\(c.id)", section: section, title: c.title ?? "New chat",
                 subtitle: name(c.workspaceId), systemImage: "bubble.left",
                 workspace: byId[c.workspaceId], action: .chat(c))
        }
        var actions: [Item] = []
        if let ws = current {
            actions.append(Item(id: "new:\(ws.id)", section: .actions, title: "New chat",
                                subtitle: "in \(ws.isComputer ? "Computer" : ws.name)",
                                systemImage: "square.and.pencil", workspace: nil, action: .newChat(ws)))
        }
        actions.append(Item(id: "settings", section: .actions, title: "Settings", subtitle: nil,
                            systemImage: "gearshape", workspace: nil, action: .settings))

        let newestFirst = chats.sorted { $0.updatedAt > $1.updatedAt }
        if query.isEmpty {
            // Where you are likely going: the last few conversations, then actions.
            return newestFirst.prefix(8).map { chatItem($0, .recent) } + actions
        }
        let foundChats = newestFirst
            .filter { matches(query, "\($0.title ?? "New chat") \(name($0.workspaceId))") }
            .prefix(20)
            .map { chatItem($0, .chats) }
        let foundProjects = workspaces
            .filter { !$0.isComputer && matches(query, $0.name) }
            .map { ws in
                Item(id: "project:\(ws.id)", section: .projects, title: ws.name, subtitle: nil,
                     systemImage: "folder", workspace: ws, action: .project(ws))
            }
        let foundActions = actions.filter { matches(query, "\($0.title) \($0.subtitle ?? "")") }
        return foundChats + foundProjects + foundActions
    }
}
