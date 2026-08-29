import SwiftUI

/// Rows and chips shared by the sidebar and the project screens.
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
