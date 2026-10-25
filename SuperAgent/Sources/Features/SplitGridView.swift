import SwiftUI

/// Where a split row goes on the phone: its grid.
struct SplitRoute: Hashable {
    let id: String
}

/// A Mac split on a small screen: no windows side by side, a grid of its
/// conversations. Tap one and it opens on its own; Back returns to the grid.
struct SplitGridView: View {
    let connection: Connection
    let splitId: String
    let open: (WireChat) -> Void

    private var split: WireSplit? { connection.splits.first { $0.id == splitId } }

    private var chats: [WireChat] {
        (split?.tiles ?? []).compactMap { t in connection.chats.first { $0.id == t.chatId } }
    }

    private func project(of chat: WireChat) -> String {
        if chat.workspaceId == "__desktop_chat__" { return "Chats" }
        return connection.tree.flatMap(\.workspaces).first { $0.id == chat.workspaceId }?.name ?? "Project"
    }

    var body: some View {
        ScrollView {
            if chats.isEmpty {
                Text("This split has no conversations left.")
                    .superFont(14).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(chats.enumerated()), id: \.element.id) { i, chat in
                        card(chat, number: i + 1)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.panel)
        .navigationTitle(split?.name ?? "Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func card(_ chat: WireChat, number: Int) -> some View {
        Button { open(chat) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(number)").superFont(11, weight: .semibold)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(project(of: chat)).superFont(11.5).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    Spacer(minLength: 0)
                    if chat.live { ProgressView().controlSize(.mini) }
                    UnreadDot(on: connection.unread.isUnread(chat))
                }
                Text(chat.title ?? "New chat")
                    .superFont(15, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let preview = chat.preview, !preview.isEmpty {
                    Text(preview)
                        .superFont(12.5).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("split-card-\(chat.id)")
    }
}
