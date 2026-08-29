import SwiftUI

/// The conversations of one project — title, what was last said, when, and a
/// waveform when the agent is alive in it. Swipe to rename or delete.
struct ChatListView: View {
    let connection: Connection
    let workspace: WireWorkspace
    @State private var creating = false
    @State private var error: String?
    @State private var renaming: WireChat?
    @State private var newTitle = ""
    @State private var deleting: WireChat?

    private var chats: [WireChat] {
        connection.chats.filter { $0.workspaceId == workspace.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            if chats.isEmpty {
                ContentUnavailableView("No conversations", systemImage: "bubble.left",
                                       description: Text("Start one with the pencil above."))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(chats) { chat in
                        NavigationLink(value: chat) { ChatRow(chat: chat) }
                            .listRowBackground(Theme.card)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleting = chat } label: { Label("Delete", systemImage: "trash") }
                                Button { newTitle = chat.title ?? ""; renaming = chat } label: { Label("Rename", systemImage: "pencil") }
                                    .tint(Theme.textSecondary)
                            }
                            .contextMenu {
                                Button { newTitle = chat.title ?? ""; renaming = chat } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = chat } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle(workspace.isBrowser ? (workspace.host ?? workspace.name) : workspace.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: WireChat.self) { chat in
            ChatView(connection: connection, chat: chat, workspace: workspace)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        creating = true
                        defer { creating = false }
                        do { _ = try await connection.createChat(workspaceId: workspace.id); Haptics.tap() }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { Image(systemName: "square.and.pencil") }
                .disabled(creating || connection.state != .connected)
                .accessibilityLabel("New conversation")
            }
        }
        .alert("Rename conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let chat = renaming, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Task { do { try await connection.renameChat(chatId: chat.id, title: newTitle) } catch { self.error = error.localizedDescription } }
                }
                renaming = nil
            }
        }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let chat = deleting { Task { do { try await connection.deleteChat(chatId: chat.id) } catch { self.error = error.localizedDescription } } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("It disappears from the Mac too. The agent's session ends.") }
        .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}

struct ChatRow: View {
    let chat: WireChat
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chat.title ?? "New conversation")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if chat.live { Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(Theme.working) }
                }
                Text(chat.preview?.isEmpty == false ? chat.preview! : "Nothing said yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(Date(timeIntervalSince1970: chat.updatedAt / 1000), format: .relative(presentation: .named))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
