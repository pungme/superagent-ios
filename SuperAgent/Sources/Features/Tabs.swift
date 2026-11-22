import SwiftUI

/// The Chat tab: the Computer's conversation list. A tab is a destination,
/// not a particular session; tapping a row pushes that session and Back comes
/// here again.
struct ComputerChatsTab: View {
    let connection: Connection
    @Binding var path: NavigationPath

    private var computer: WireWorkspace? {
        connection.tree.first { $0.id == "computer" }?.workspaces.first
    }
    var body: some View {
        Group {
            if let computer {
                ChatsListView(connection: connection, workspace: computer) { chat in
                    path.append(chat)
                }
            } else {
                ContentUnavailableView("No Mac yet", systemImage: "desktopcomputer",
                                       description: Text("Connect to your Mac and its Computer conversation appears here."))
                    .background(Theme.panel)
            }
        }
    }
}

/// The Search tab: every conversation on the Mac, from one field. The sidebar
/// used to hold this in its navigation-bar drawer; a tab gives it a permanent
/// home and the drawer's quirks go with it.
struct SearchTabView: View {
    let connection: Connection
    @Binding var path: NavigationPath
    /// The palette's own doors, as ⌘K has them: the project you are in (for
    /// "New chat"), a project, a new chat, Settings.
    var current: WireWorkspace? = nil
    var openProject: (WireWorkspace) -> Void = { _ in }
    var newChat: (WireWorkspace) -> Void = { _ in }
    var openSettings: () -> Void = {}
    @Environment(AppState.self) private var app

    @State private var query = ""
    @State private var hits: [WireSearchHit] = []

    var body: some View {
        List {
            // Like ⌘K: recent conversations and actions before you type, then
            // chats, projects and actions that match, then what was said.
            ForEach(items) { item in
                if items.first(where: { $0.section == item.section })?.id == item.id {
                    SmallCapsHeader(title: item.section.rawValue)
                        .listRowBackground(Theme.panel).listRowSeparator(.hidden)
                }
                paletteRow(item)
                    .listRowBackground(Theme.card)
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                if items.isEmpty && hits.isEmpty {
                    Text("Nothing matches").foregroundStyle(.secondary)
                        .listRowBackground(Theme.panel)
                }
                if !hits.isEmpty {
                    SmallCapsHeader(title: "What was said")
                        .listRowBackground(Theme.panel).listRowSeparator(.hidden)
                }
            }
            ForEach(hits) { hit in
                Button { open(hit) } label: {
                    HStack(alignment: .top, spacing: 10) {
                    SearchHitGlyph(connection: connection, workspaceId: hit.workspaceId).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(hit.title ?? "New chat").superFont(13.5, weight: .medium)
                                .foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                            Text(Date(timeIntervalSince1970: hit.ts / 1000), format: .relative(presentation: .named))
                                .superFont(11).foregroundStyle(Theme.textTertiary)
                        }
                        Text(hit.snippet).superFont(12).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.hoverPlain)
                .listRowBackground(Theme.card)
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.border)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Go to a chat or project, or search what was said")
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            hits = (try? await connection.searchChats(q)) ?? []
        }
    }

    private var items: [CommandPaletteModel.Item] {
        CommandPaletteModel.items(
            query: query,
            chats: connection.chats,
            workspaces: connection.tree.flatMap(\.workspaces),
            current: current)
    }

    private func paletteRow(_ item: CommandPaletteModel.Item) -> some View {
        Button {
            switch item.action {
            case let .chat(chat): path.append(chat)
            case let .project(ws): openProject(ws)
            case let .newChat(ws): newChat(ws)
            case .settings: openSettings()
            }
        } label: {
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
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.hoverPlain)
        .accessibilityIdentifier("palette-row")
    }

    private func open(_ hit: WireSearchHit) {
        if let chat = connection.chats.first(where: { $0.id == hit.chatId }) {
            path.append(chat)
        } else {
            // A chat the list has not caught up to yet: let the pending-open
            // path fetch and route it, same as a tapped notification.
            app.openChatId = hit.chatId
        }
    }
}

/// The Today tab: the day on one screen, as on the Mac. What needs you first,
/// then the calendar, every project's open to-dos, the agents at work, and the
/// recent conversations (what the Activity tab listed).
struct TodayTab: View {
    let connection: Connection
    @Binding var path: NavigationPath

    @State private var today: WireToday?
    @State private var error: String?
    @State private var handing: String?
    @State private var draft = ""
    @State private var asking = false

    private static func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    private static func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private var workspaces: [WireWorkspace] { connection.tree.flatMap(\.workspaces) }
    private func name(_ id: String) -> String { workspaces.first { $0.id == id }?.name ?? "Chats" }
    private var needing: [WireWorkspace] { workspaces.filter { $0.status == .needsYou } }
    private var working: [WireChat] { connection.chats.filter(\.live) }
    private var recent: [WireChat] {
        connection.chats.filter { !$0.live }.sorted { $0.updatedAt > $1.updatedAt }.prefix(12).map { $0 }
    }

    var body: some View {
        let now = Date()
        let nowMin = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        List {
            if !needing.isEmpty {
                Section {
                    ForEach(needing) { ws in
                        Button {
                            if let chat = connection.chats.filter({ $0.workspaceId == ws.id }).max(by: { $0.updatedAt < $1.updatedAt }) {
                                path.append(chat)
                            }
                        } label: {
                            HStack {
                                Circle().fill(Theme.needsYou).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(ws.name) needs you").font(.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    Text("Open it to answer").font(.footnote).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .listRowBackground(Theme.needsYou.opacity(0.14))
                    }
                }
            }
            Section {
                if let events = today?.events, !events.isEmpty {
                    ForEach(events) { e in
                        HStack(spacing: 10) {
                            Text(e.allDay ? "All day" : Self.hhmm(e.startMinutes))
                                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                .frame(width: 50, alignment: .leading)
                            RoundedRectangle(cornerRadius: 2).fill(Color(hexString: e.color) ?? .blue).frame(width: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).foregroundStyle(Theme.textPrimary)
                                let mins = max(e.endMinutes - e.startMinutes, 0)
                                let note = e.notes.split(separator: "\n").first.map(String.init) ?? ""
                                Text([e.allDay ? "" : (mins >= 60 ? String(format: "%g h", (Double(mins) / 60 * 10).rounded() / 10) : "\(mins) min"), note]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if !e.allDay, e.startMinutes > nowMin, e.id == events.first(where: { !$0.allDay && $0.startMinutes > nowMin })?.id {
                                let left = e.startMinutes - nowMin
                                Text(left >= 60 ? "in \(left / 60) h \(left % 60)" : "in \(left) min")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                            }
                        }
                        .opacity(!e.allDay && e.endMinutes <= nowMin ? 0.45 : 1)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text(today == nil && error == nil ? "Loading…" : "Nothing on the calendar today.").foregroundStyle(.secondary)
                }
            } header: { SmallCapsHeader(title: "Calendar") }
            .listRowBackground(Theme.card)

            Section {
                if let cards = today?.cards, !cards.isEmpty {
                    ForEach(cards) { c in
                        HStack(spacing: 10) {
                            Button { tick(c) } label: {
                                Image(systemName: "circle").font(.title3).foregroundStyle(Theme.textTertiary)
                            }
                            .buttonStyle(.hoverPlain).accessibilityLabel("Done: \(c.title)")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).foregroundStyle(Theme.textPrimary).lineLimit(2)
                                Text(name(c.workspaceId)).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 6)
                            if let chatId = c.chatId, let chat = connection.chats.first(where: { $0.id == chatId }) {
                                Button { path.append(chat) } label: {
                                    Text(chat.live ? "Working" : "Open chat").font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.14), in: Capsule()).foregroundStyle(.blue)
                                }
                                .buttonStyle(.hoverPlain)
                            } else {
                                Button { hand(c) } label: {
                                    Text(handing == c.id ? "Handing…" : "Hand to agent").font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.accentFg)
                                }
                                .buttonStyle(.hoverPlain).disabled(handing != nil || connection.state != .connected)
                                .accessibilityIdentifier("hand-\(c.id)")
                            }
                        }
                    }
                } else {
                    Text(today == nil && error == nil ? "Loading…" : "No open to-dos in any project.").foregroundStyle(.secondary)
                }
            } header: { SmallCapsHeader(title: "To-do") }
            .listRowBackground(Theme.card)

            if !working.isEmpty {
                Section {
                    ForEach(working) { c in chatRow(c, note: "working") }
                } header: { SmallCapsHeader(title: "Agents") }
                .listRowBackground(Theme.card)
            }
            if !recent.isEmpty {
                Section {
                    ForEach(recent) { c in chatRow(c, note: nil) }
                } header: { SmallCapsHeader(title: "Recent") }
                .listRowBackground(Theme.card)
            }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.danger) }.listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) { MacBatteryBadge(battery: connection.battery).fixedSize() }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                TextField("Ask about your day, or anything", text: $draft)
                    .textFieldStyle(.plain).submitLabel(.send).onSubmit(ask)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                    .accessibilityIdentifier("today-ask")
                Button(action: ask) {
                    Image(systemName: "arrow.up").font(.body.weight(.bold))
                        .frame(width: 36, height: 36)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.accentSoft : Theme.accent, in: Circle())
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textTertiary : Theme.accentFg)
                }
                .buttonStyle(.hoverPlain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || asking || connection.state != .connected)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.panel)
        }
        .refreshable { await load() }
        .task(id: connection.state == .connected) {
            // Kept fresh while the tab is on screen: the Mac's lists change under it.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func chatRow(_ c: WireChat, note: String?) -> some View {
        Button { path.append(c) } label: {
            HStack(spacing: 10) {
                Circle().fill(note != nil ? Color.blue : Theme.textTertiary.opacity(0.5)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title ?? "New chat").foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(name(c.workspaceId)).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let note {
                    Text(note).font(.footnote).foregroundStyle(Theme.textSecondary)
                } else {
                    Text(Date(timeIntervalSince1970: c.updatedAt / 1000), format: .relative(presentation: .named))
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func load() async {
        guard connection.state == .connected else { return }
        do {
            today = try await connection.loadToday(date: Self.ymd(Date()))
            error = nil
        } catch {
            if today == nil { self.error = "The Mac could not send today. It may need a newer Superagent." }
        }
    }

    private func tick(_ c: WireCard) {
        today?.cards.removeAll { $0.id == c.id }
        Haptics.tap()
        Task {
            do { _ = try await connection.moveCard(id: c.id, to: .done) }
            catch { self.error = error.localizedDescription; await load() }
        }
    }

    private func hand(_ c: WireCard) {
        handing = c.id
        Task {
            defer { handing = nil }
            do {
                let chatId = try await connection.handToAgent(card: c)
                if let i = today?.cards.firstIndex(where: { $0.id == c.id }) {
                    today?.cards[i].chatId = chatId
                    today?.cards[i].status = .doing
                }
                Haptics.success()
            } catch let e as RpcError { error = e.message } catch { self.error = error.localizedDescription }
        }
    }

    private func ask() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !asking else { return }
        asking = true
        Task {
            defer { asking = false }
            do {
                let chatId = try await connection.askToday(text)
                draft = ""
                if let chat = connection.chats.first(where: { $0.id == chatId }) { path.append(chat) }
            } catch let e as RpcError { error = e.message } catch { self.error = error.localizedDescription }
        }
    }
}

private extension Color {
    /// "#22b573" → a colour; nil for anything else.
    init?(hexString: String?) {
        guard let h = hexString?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
