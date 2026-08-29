import SwiftUI

/// One project, the way the desktop shows it: conversations first, then the
/// files, the board and the routines behind a segmented control. The branch
/// chip in the bar switches branches.
struct WorkspaceView: View {
    let connection: Connection
    let workspace: WireWorkspace

    enum Tab: String, CaseIterable, Identifiable {
        case chats = "Chats", files = "Files", board = "Board", routines = "Routines"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .chats
    @State private var showBranches = false

    /// The tree refreshes after a checkout; read the live row, not the one we were pushed with.
    private var live: WireWorkspace {
        connection.tree.flatMap(\.workspaces).first { $0.id == workspace.id } ?? workspace
    }
    private var title: String { live.isBrowser ? (live.host ?? live.name) : live.name }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
            .background(Theme.panel)
            switch tab {
            case .chats: ChatListView(connection: connection, workspace: live)
            case .files: FilesView(connection: connection, workspace: live)
            case .board: BoardView(connection: connection, workspace: live)
            case .routines: RoutinesView(connection: connection, workspace: live)
            }
        }
        .background(Theme.panel)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let b = live.branch, !b.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showBranches = true } label: { BranchChip(branch: b) }
                        .accessibilityLabel("Branch \(b)")
                }
            }
        }
        .sheet(isPresented: $showBranches) { BranchSheet(connection: connection, workspace: live) }
        .navigationDestination(for: WireChat.self) { chat in
            ChatView(connection: connection, chat: chat, workspace: live)
        }
        .navigationDestination(for: FileRef.self) { ref in
            FileView(connection: connection, ref: ref)
        }
    }
}
