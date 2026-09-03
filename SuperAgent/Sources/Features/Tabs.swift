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
    @Environment(AppState.self) private var app

    @State private var query = ""
    @State private var hits: [WireSearchHit] = []

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search every conversation", systemImage: "magnifyingglass",
                                       description: Text("Titles and what was said, across every project on \(connection.machine.name)."))
                    .listRowBackground(Theme.panel)
                    .listRowSeparator(.hidden)
            } else if hits.isEmpty {
                Text("Nothing matches").foregroundStyle(.secondary)
                    .listRowBackground(Theme.panel)
            }
            ForEach(hits) { hit in
                Button { open(hit) } label: {
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
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.border)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search every conversation")
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            hits = (try? await connection.searchChats(q)) ?? []
        }
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
