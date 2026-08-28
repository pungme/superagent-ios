import SwiftUI

/// The conversations of one project. Newest first; a running one is marked.
struct ChatListView: View {
    let connection: Connection
    let workspace: WireWorkspace
    @State private var creating = false
    @State private var error: String?

    private var chats: [WireChat] {
        connection.chats.filter { $0.workspaceId == workspace.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            ForEach(chats) { chat in
                NavigationLink(value: chat) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.title ?? "New conversation").lineLimit(1)
                            Text(Date(timeIntervalSince1970: chat.updatedAt / 1000), style: .relative)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if chat.live {
                            Image(systemName: "waveform").foregroundStyle(.green).font(.caption)
                        }
                    }
                }
            }
            if chats.isEmpty {
                ContentUnavailableView("No conversations", systemImage: "bubble.left", description: Text("Start one below."))
            }
        }
        .navigationTitle(workspace.name)
        .navigationDestination(for: WireChat.self) { chat in
            ChatView(connection: connection, chat: chat, workspace: workspace)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        creating = true
                        defer { creating = false }
                        do { _ = try await connection.createChat(workspaceId: workspace.id) }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { Image(systemName: "square.and.pencil") }
                .disabled(creating || connection.state != .connected)
                .accessibilityLabel("New conversation")
            }
        }
        .alert("Couldn't start a conversation", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}
