import SwiftUI

/// The Chat app's list, as on the desktop (DesktopChat.tsx): "+ New chat" on
/// top, then the conversations newest first — title, when it last moved, and
/// what was last said. Tap one to open it; swipe to rename or delete.
struct ChatsListView: View {
    let connection: Connection
    let workspace: WireWorkspace
    let open: (WireChat) -> Void

    @State private var creating = false
    @State private var renaming: WireChat?
    @State private var newTitle = ""
    @State private var deleting: WireChat?
    @State private var error: String?

    private var chats: [WireChat] {
        connection.chats.filter { $0.workspaceId == workspace.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Button { newChat() } label: {
                Text("+ New chat").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(creating || connection.state != .connected)
            .listRowBackground(Theme.card)

            if chats.isEmpty {
                Text("No conversations yet.").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .listRowBackground(Theme.card)
            }
            ForEach(chats) { chat in
                Button { open(chat) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(chat.title ?? "New chat")
                                .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            if chat.live { ProgressView().controlSize(.mini) }
                            Spacer()
                            Text(Date(timeIntervalSince1970: chat.updatedAt / 1000), format: .relative(presentation: .named))
                                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        if let p = chat.preview, !p.isEmpty {
                            Text(p).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deleting = chat } label: { Label("Delete", systemImage: "trash") }
                    Button { newTitle = chat.title ?? ""; renaming = chat } label: { Label("Rename", systemImage: "pencil") }
                        .tint(Theme.textSecondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { PanelTitle(title: "Chats", subtitle: connection.machine.name) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newChat() } label: { Image(systemName: "square.and.pencil") }
                    .disabled(creating || connection.state != .connected)
                    .accessibilityLabel("New chat")
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
        .confirmationDialog("Delete \"\(deleting?.title ?? "New chat")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let chat = deleting { Task { do { try await connection.deleteChat(chatId: chat.id) } catch { self.error = error.localizedDescription } } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("A conversation is work; this can't be undone.") }
        .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func newChat() {
        guard !creating else { return }
        creating = true
        Task {
            defer { creating = false }
            do {
                let id = try await connection.createChat(workspaceId: workspace.id)
                if let c = connection.chats.first(where: { $0.id == id }) { open(c) }
                Haptics.tap()
            } catch { self.error = error.localizedDescription }
        }
    }
}
