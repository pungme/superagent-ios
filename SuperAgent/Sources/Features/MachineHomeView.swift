import SwiftUI

/// The desktop sidebar, as a phone screen: groups in small caps, projects with
/// a folder (or the site's favicon), the branch chip, and the same status
/// language — a spinner while the agent works, a dot when it needs you.
struct MachineHomeView: View {
    let connection: Connection
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var hits: [WireSearchHit] = []
    @State private var searching = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if connection.state != .connected {
                    ConnectionBanner(connection: connection)
                        .padding(14)
                        .superCard()
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResults(hits: hits, searching: searching, workspaces: connection.tree.flatMap(\.workspaces)) { hit in
                        query = ""
                        app.openChatId = hit.chatId
                    }
                }
                ForEach(query.isEmpty ? connection.tree : []) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        GroupLabel(text: group.name).padding(.leading, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(group.workspaces.enumerated()), id: \.element.id) { i, ws in
                                NavigationLink(value: ws) {
                                    ProjectRow(workspace: ws, chats: chats(for: ws.id))
                                }
                                .buttonStyle(.plain)
                                if i < group.workspaces.count - 1 {
                                    Divider().overlay(Theme.border).padding(.leading, 52)
                                }
                            }
                            if group.workspaces.isEmpty {
                                Text("Add a project on the Mac and it appears here.")
                                    .font(.footnote).foregroundStyle(Theme.textTertiary)
                                    .padding(14)
                            }
                        }
                        .superCard()
                    }
                }
                if connection.state == .connected, connection.tree.isEmpty {
                    ContentUnavailableView("No projects yet", systemImage: "folder",
                                           description: Text("Add a project on the Mac and it appears here."))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.panel)
        .navigationTitle(connection.machine.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionPill(state: connection.state)
            }
        }
        .navigationDestination(for: WireWorkspace.self) { ws in
            WorkspaceView(connection: connection, workspace: ws)
        }
        .refreshable { connection.connect() }
        .searchable(text: $query, prompt: "Search every conversation")
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { hits = []; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            hits = (try? await connection.searchChats(q)) ?? []
            searching = false
        }
    }

    private func chats(for workspaceId: String) -> [WireChat] {
        connection.chats.filter { $0.workspaceId == workspaceId }
    }
}

/// What the search box found, newest first; tapping opens the conversation.
private struct SearchResults: View {
    let hits: [WireSearchHit]
    let searching: Bool
    let workspaces: [WireWorkspace]
    let open: (WireSearchHit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel(text: searching && hits.isEmpty ? "SEARCHING…" : (hits.isEmpty ? "NO MATCHES" : "\(hits.count) MATCH\(hits.count == 1 ? "" : "ES")")).padding(.leading, 6)
            if !hits.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                        Button { open(hit) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(hit.title ?? "New conversation").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: hit.ts / 1000), format: .relative(presentation: .named))
                                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                                }
                                Text(hit.snippet).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                                if let ws = workspaces.first(where: { $0.id == hit.workspaceId }) {
                                    Text((ws.isBrowser ? ws.host ?? ws.name : ws.name) + " · " + (hit.role == "user" ? "you said" : "the agent said"))
                                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < hits.count - 1 { Divider().overlay(Theme.border).padding(.leading, 14) }
                    }
                }
                .superCard()
            }
        }
    }
}

struct ProjectRow: View {
    let workspace: WireWorkspace
    let chats: [WireChat]

    var body: some View {
        HStack(spacing: 12) {
            ProjectIcon(workspace: workspace)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(workspace.isBrowser ? (workspace.host ?? workspace.name) : workspace.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let b = workspace.branch, !b.isEmpty { BranchChip(branch: b) }
                }
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusIndicator(status: workspace.status)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        switch workspace.status {
        case .working: return "Working…"
        case .needsYou: return "Needs you"
        case .idle:
            let live = chats.filter(\.live).count
            if let p = chats.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.preview, !p.isEmpty { return p }
            if live > 0 { return "\(live) running" }
            return chats.isEmpty ? "No conversations yet" : "\(chats.count) conversation\(chats.count == 1 ? "" : "s")"
        }
    }
}

/// Folder for a code project; the site's favicon for a browser project.
struct ProjectIcon: View {
    let workspace: WireWorkspace
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accentSoft)
            if workspace.isBrowser, let host = workspace.host, let url = URL(string: "https://\(host)/favicon.ico") {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFit().padding(6) }
                    else { letter(host) }
                }
            } else {
                Image(systemName: "folder").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 30, height: 30)
    }
    private func letter(_ host: String) -> some View {
        Text(String(host.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
    }
}

struct ConnectionPill: View {
    let state: Connection.State
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.accentSoft, in: Capsule())
    }
    private var color: Color {
        switch state { case .connected: Theme.working; case .connecting: Theme.needsYou; default: Theme.textTertiary }
    }
    private var label: String {
        switch state { case .connected: "Live"; case .connecting: "Connecting"; case .machineOffline: "Mac asleep"; default: "Offline" }
    }
}

struct ConnectionBanner: View {
    let connection: Connection
    var body: some View {
        HStack(spacing: 12) {
            if connection.state == .connecting { ProgressView() }
            else { Image(systemName: icon).foregroundStyle(Theme.needsYou) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if connection.state != .connecting {
                Button("Retry") { connection.connect() }.font(.caption.weight(.semibold)).tint(Theme.textPrimary)
            }
        }
    }
    private var icon: String {
        switch connection.state {
        case .machineOffline: "moon.zzz"
        case .failed: "exclamationmark.triangle"
        default: "wifi.slash"
        }
    }
    private var title: String {
        switch connection.state {
        case .connecting: "Connecting…"
        case .machineOffline: "\(connection.machine.name) is unreachable"
        case .failed(let r): r == "revoked" || r == "unauthorized" ? "This phone was removed on the Mac" : "Connection failed"
        default: "Not connected"
        }
    }
    private var detail: String {
        switch connection.state {
        case .machineOffline: "Asleep, offline, or SuperAgent isn't running. You can still read what's here."
        case .failed(let r): r == "version" ? "Update the app to talk to this Mac." : (connection.lastError ?? r)
        default: connection.lastError ?? "Through \(connection.machine.relay)"
        }
    }
}
