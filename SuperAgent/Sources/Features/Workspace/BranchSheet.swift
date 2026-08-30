import SwiftUI

/// Local branches; tap one to check it out on the Mac. Git's own refusal
/// (dirty tree, branch in a worktree) is shown verbatim.
struct BranchSheet: View {
    let connection: Connection
    let workspace: WireWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var branches: [WireBranch] = []
    @State private var loading = true
    @State private var switching: String?
    @State private var confirm: WireBranch?
    @State private var error: String?

    /// One branch. Named to keep `body` small enough to type-check quickly on
    /// any machine, not just a fast one.
    @ViewBuilder
    private func branchRow(_ b: WireBranch) -> some View {
        Button {
            if !b.current { confirm = b }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.name).foregroundStyle(Theme.textPrimary)
                    if let wt = b.worktree, !wt.isEmpty, !b.current {
                        let leaf = wt.split(separator: "/").last.map(String.init) ?? wt
                        Text("Checked out in " + leaf)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if switching == b.name {
                    ProgressView()
                } else if b.current {
                    Image(systemName: "checkmark").foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .disabled(switching != nil)
    }

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Reading branches…").foregroundStyle(.secondary) }
                } else if branches.isEmpty {
                    Text("No branches — is this folder a git repo?").foregroundStyle(.secondary)
                } else {
                    ForEach(branches) { b in branchRow(b) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .confirmationDialog("Switch to \(confirm?.name ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                Button("Switch branch") { if let b = confirm { checkout(b) }; confirm = nil }
                Button("Cancel", role: .cancel) { confirm = nil }
            } message: { Text("The Mac's working copy changes; a running agent keeps going on the new branch.") }
            .alert("Git refused", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func load() async {
        do { branches = try await connection.branches(workspaceId: workspace.id) } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func checkout(_ b: WireBranch) {
        switching = b.name
        Task {
            defer { switching = nil }
            do {
                try await connection.checkout(workspaceId: workspace.id, branch: b.name)
                Haptics.success()
                await load()
            } catch { self.error = error.localizedDescription; Haptics.warning() }
        }
    }
}
