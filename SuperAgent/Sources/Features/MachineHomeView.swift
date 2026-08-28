import SwiftUI

/// Projects on one Mac, grouped like the desktop sidebar, with each agent's status.
struct MachineHomeView: View {
    let connection: Connection

    var body: some View {
        List {
            if connection.state != .connected {
                Section { ConnectionBanner(connection: connection) }
            }
            ForEach(connection.tree) { group in
                Section(group.name) {
                    ForEach(group.workspaces) { ws in
                        NavigationLink(value: ws) {
                            HStack(spacing: 12) {
                                StatusDot(status: ws.status)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ws.name).font(.body)
                                    Text(statusLabel(ws.status, live: chatsLive(ws.id)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if connection.state == .connected, connection.tree.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "folder", description: Text("Add a project on the Mac and it appears here."))
            }
        }
        .navigationTitle(connection.machine.name)
        .navigationDestination(for: WireWorkspace.self) { ws in
            ChatListView(connection: connection, workspace: ws)
        }
        .refreshable { connection.connect() }
    }

    private func chatsLive(_ workspaceId: String) -> Int {
        connection.chats.filter { $0.workspaceId == workspaceId && $0.live }.count
    }

    private func statusLabel(_ s: WorkspaceStatus, live: Int) -> String {
        switch s {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .idle: live > 0 ? "Idle · \(live) running" : "Idle"
        }
    }
}

struct StatusDot: View {
    let status: WorkspaceStatus
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 3).opacity(status == .working ? 1 : 0))
            .accessibilityLabel(Text(status.rawValue))
    }
    private var color: Color {
        switch status {
        case .idle: .secondary.opacity(0.5)
        case .working: .green
        case .needsYou: .orange
        }
    }
}

struct ConnectionBanner: View {
    let connection: Connection
    var body: some View {
        HStack(spacing: 12) {
            if connection.state == .connecting { ProgressView() }
            else { Image(systemName: icon).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if connection.state != .connecting {
                Button("Retry") { connection.connect() }.font(.caption.weight(.semibold))
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
