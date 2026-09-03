import SwiftUI

/// What you shared, waiting to be aimed.
///
/// Appears when the app comes forward with something in the share inbox.
/// Each item goes wherever you point it — any project, any chat, or a new
/// chat — because a chat only knows its own project, so the app cannot guess.
/// Closing the sheet keeps the items; they will be here next time, so a share
/// made today can start a session next week.
struct ShareInboxSheet: View {
    let connection: Connection
    @State private var items: [ShareInbox.Item] = ShareInbox.items()
    @State private var aiming: ShareInbox.Item?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button { aiming = item } label: { row(item) }
                        .listRowBackground(Theme.card)
                }
                .onDelete { idx in
                    for i in idx { ShareInbox.remove(items[i]) }
                    items.remove(atOffsets: idx)
                    if items.isEmpty { dismiss() }
                }
                Section {
                    Text("Items stay here until you send or delete them — you can decide in a later session.")
                        .superFont(12.5).foregroundStyle(Theme.textTertiary)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Shared with Superagent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
            .sheet(item: $aiming) { item in
                ShareDestinationSheet(connection: connection, item: item) { sent in
                    if sent {
                        ShareInbox.remove(item)
                        items.removeAll { $0.id == item.id }
                        if items.isEmpty { dismiss() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ShareInbox.Item) -> some View {
        HStack(spacing: 10) {
            if let data = ShareInbox.imageData(item), let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(item.text.isEmpty ? "Image" : item.text)
                .superFont(14.5).foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
            Spacer()
            Image(systemName: "arrow.forward.circle").foregroundStyle(Theme.accent)
        }
    }
}

/// Pick the project, then the chat — existing or new — and off it goes.
private struct ShareDestinationSheet: View {
    let connection: Connection
    let item: ShareInbox.Item
    let onDone: (Bool) -> Void
    @State private var sending = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var workspaces: [WireWorkspace] {
        connection.tree.filter { $0.id != "computer" }.flatMap(\.workspaces)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(workspaces) { ws in
                    Section(ws.name) {
                        Button { send(to: nil, in: ws) } label: {
                            Label("New chat", systemImage: "plus.bubble")
                                .foregroundStyle(Theme.accent)
                        }
                        .listRowBackground(Theme.card)
                        ForEach(chats(in: ws)) { chat in
                            Button { send(to: chat.id, in: ws) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title ?? "Untitled chat")
                                        .superFont(14.5).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    if let p = chat.preview, !p.isEmpty {
                                        Text(p).superFont(12).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                    }
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Send to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            }
            .overlay { if sending { ProgressView() } }
            .disabled(sending)
            .alert("Could not send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func chats(in ws: WireWorkspace) -> [WireChat] {
        connection.chats.filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func send(to chatId: String?, in ws: WireWorkspace) {
        sending = true
        Task {
            do {
                let target: String
                if let chatId { target = chatId } else {
                    target = try await connection.createChat(workspaceId: ws.id)
                }
                let images: [(mediaType: String, data: Data)] =
                    ShareInbox.imageData(item).map { [(mediaType: "image/jpeg", data: $0)] } ?? []
                connection.sendMessage(chatId: target, text: item.text, images: images)
                Haptics.tap()
                dismiss()
                onDone(true)
            } catch {
                self.error = error.localizedDescription
                sending = false
            }
        }
    }
}
