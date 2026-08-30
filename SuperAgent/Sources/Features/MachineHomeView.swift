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
                        .superFont(16, weight: .medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let b = workspace.branch, !b.isEmpty { BranchChip(branch: b) }
                }
                Text(subtitle)
                    .superFont(13)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusIndicator(status: workspace.status)
            Image(systemName: "chevron.right").superFont(12, weight: .semibold).foregroundStyle(Theme.textTertiary)
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
    @ScaledMetric(relativeTo: .subheadline) private var box: CGFloat = 30

    let workspace: WireWorkspace
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accentSoft)
            if workspace.isBrowser, let host = workspace.host, let url = URL(string: "https://\(host)/favicon.ico") {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFit().padding(6) }
                    else { letter(host) }
                }
            } else if workspace.isBrowser {
                Image(systemName: "globe").superFont(14, weight: .medium).foregroundStyle(Theme.textSecondary)
            } else if workspace.isComputer {
                Image(systemName: "desktopcomputer").superFont(14, weight: .medium).foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "folder").superFont(14, weight: .medium).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: box, height: box)
    }
    private func letter(_ host: String) -> some View {
        Text(String(host.prefix(1)).uppercased()).superFont(13, weight: .bold).foregroundStyle(Theme.textSecondary)
    }
}

struct ConnectionPill: View {
    let state: Connection.State
    static func color(for state: Connection.State) -> Color {
        switch state { case .connected: Theme.working; case .connecting: Theme.needsYou; default: Theme.textTertiary }
    }
    static func label(for state: Connection.State) -> String {
        switch state { case .connected: "Live"; case .connecting: "Connecting"; case .machineOffline: "Mac asleep"; default: "Offline" }
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).superFont(12, weight: .medium).foregroundStyle(Theme.textSecondary)
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
    /// At the accessibility sizes the row cannot hold icon, two lines of text
    /// and Retry side by side — "Not connected" comes out as "Not c…". Stack it
    /// instead, which is what the rest of iOS does with a control in a row.
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        return AnyLayout(stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                 : AnyLayout(HStackLayout(spacing: 12))) {
            HStack(spacing: 12) {
                // The glyph stops growing where the words still need the room.
                Group {
                    if connection.state == .connecting { ProgressView() }
                    else { Image(systemName: icon).foregroundStyle(Theme.needsYou) }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !stacked { Spacer() }
            }
            if connection.state != .connecting {
                Button("Retry") { connection.connect() }.font(.caption.weight(.semibold)).tint(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .machineOffline: "Asleep, offline, or Superagent isn't running. You can still read what's here."
        case .failed(let r): r == "version" ? "Update the app to talk to this Mac." : (connection.lastError ?? r)
        default: connection.lastError ?? "Through \(connection.machine.relay)"
        }
    }
}
