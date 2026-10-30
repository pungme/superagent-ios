import SwiftUI

/// How full an allowance is, in the colour that says so: quiet, then amber
/// from 75%, red from 90%. The same thresholds as the Mac.
func usageColour(_ percent: Int) -> Color {
    percent >= 90 ? Theme.danger : percent >= 75 ? Theme.needsYou : Theme.textSecondary
}

/// "6 PM" when it starts over today, "Mon 10 PM" otherwise.
func usageResetLabel(_ resetsAt: Double, now: Date = .now) -> String {
    let date = Date(timeIntervalSince1970: (resetsAt / 60_000).rounded() * 60)
    let soon = date.timeIntervalSince(now) < 20 * 3600
    return soon
        ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

/// One window of an allowance: its name, a bar, the percent and when it resets.
struct UsageWindowRow: View {
    let window: WireAccount.Window

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label).superFont(12).foregroundStyle(Theme.textSecondary)
                .frame(width: 56, alignment: .leading)
            Capsule().fill(Theme.accentSoft)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(usageColour(window.percent))
                            .frame(width: geo.size.width * Double(window.percent) / 100)
                    }
                }
            Text("\(window.percent)%").superFont(12, weight: .medium)
                .foregroundStyle(usageColour(window.percent)).monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            if let r = window.resetsAt {
                Text(usageResetLabel(r)).superFont(11).foregroundStyle(Theme.textTertiary)
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }
}

/// Settings → Usage: every account each agent on the Mac can run on, with how
/// much of its allowance is used — the Mac's Settings → Agents, read-only.
struct AccountsUsageSection: View {
    let connection: Connection

    private let providers: [(id: String, name: String)] =
        [("claude", "Claude Code"), ("codex", "Codex"), ("antigravity", "Antigravity")]

    var body: some View {
        let all = connection.accounts[""]
        Section {
            if let all {
                ForEach(providers, id: \.id) { p in
                    let list = all.accounts(for: p.id)
                    if !list.isEmpty {
                        ForEach(list) { a in row(a, provider: p.name) }
                    }
                }
            } else if connection.state == .connected {
                HStack { ProgressView(); Text("Reading usage…").foregroundStyle(.secondary) }
            } else {
                Text("Connect to your Mac to see usage.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("How much of each subscription's allowance is used, as your Mac reads it. Move a chat to another account from its Account pill.")
        }
        .listRowBackground(Theme.card)
        .task(id: connection.state == .connected) {
            if connection.state == .connected { await connection.loadAccounts() }
        }
    }

    private func row(_ a: WireAccount, provider: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                ProviderMark(provider: a.provider, size: 12)
                Text(a.kind == "login" ? provider : a.name).superFont(14, weight: .medium)
                Spacer()
                if let reason = a.needsAuth {
                    Text("needs sign-in").superFont(11).foregroundStyle(Theme.danger)
                        .accessibilityHint(reason)
                }
            }
            if !a.detail.isEmpty {
                Text(a.detail).superFont(11).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            let windows = a.liveWindows()
            if windows.isEmpty {
                if a.needsAuth == nil {
                    Text("Not read yet").superFont(11).foregroundStyle(Theme.textTertiary)
                }
            } else {
                ForEach(windows, id: \.label) { UsageWindowRow(window: $0) }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usage-\(a.id)")
    }
}

// MARK: - The sidebar's usage foot

/// "5h" or "Week": short enough for the foot of the sidebar (the Mac's words).
private func shortWindow(_ label: String) -> String {
    label == "5-hour" ? "5h" : label == "Weekly" ? "Week"
        : label.hasSuffix(" weekly") ? String(label.dropLast(7)) + " week" : label
}

/// A thin bar of how much is LEFT, coloured by how much is used.
struct UsageLeftBar: View {
    let used: Int
    var body: some View {
        Capsule().fill(Theme.border)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(used >= 75 ? usageColour(used) : Theme.textTertiary)
                        .frame(width: geo.size.width * Double(max(0, 100 - used)) / 100)
                }
            }
            .accessibilityHidden(true)
    }
}

/// How much of the allowance is left, at the foot of the sidebar — the Mac's
/// UsageFooter: the account the conversation on screen is on (or, with none,
/// the one a new chat would start on), its logo, a bar and "NN% left". A tap
/// opens every account the Mac has, by agent. Hidden until the Mac says which
/// account is current, so a Mac too old to say shows nothing.
struct UsageFooter: View {
    let connection: Connection
    /// The conversation beside the sidebar (the iPad), whose account is shown.
    var chatId: String?
    @State private var showing = false

    private var live: Bool {
        #if DEBUG
        if connection.machine.id == "harness" { return true }
        #endif
        return connection.state == .connected
    }

    private var list: WireAccounts? {
        if let chatId, let l = connection.accounts[chatId], l.current != nil { return l }
        return connection.accounts[""]
    }

    private var current: WireAccount? {
        guard let list, let id = list.current else { return nil }
        return (list.claude + list.codex + list.antigravity).first { $0.id == id }
    }

    var body: some View {
        Group {
            if live, let current {
                let which = current.fullestWindow()
                let used = which?.percent
                Button { showing = true } label: {
                    HStack(spacing: 7) {
                        ProviderMark(provider: current.provider, size: 13)
                        Text(current.shortName).superFont(13).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(-1)
                        UsageLeftBar(used: used ?? 100).frame(minWidth: 24, maxWidth: 64)
                            .opacity(used == nil ? 0.4 : 1)
                        Text(used.map { "\(max(0, 100 - $0))% left" } ?? "—")
                            .superFont(13, weight: .medium).monospacedDigit()
                            .foregroundStyle(used.map { $0 >= 75 ? usageColour($0) : Theme.textTertiary } ?? Theme.textTertiary)
                            .fixedSize()
                        if let which {
                            Text(shortWindow(which.label)).superFont(11).foregroundStyle(Theme.textTertiary)
                                .fixedSize()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.hover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)
                .accessibilityIdentifier("usage-footer")
                .accessibilityLabel("\(current.shortName), \(used.map { "\(max(0, 100 - $0))% left" } ?? "usage not read yet")")
                .accessibilityHint("Shows every account's allowance")
                .sheet(isPresented: $showing) {
                    UsageSheet(connection: connection, currentId: current.id)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        // Read on connecting, then every few minutes while the sidebar is up:
        // the numbers move as the Mac works.
        .task(id: live) {
            guard live else { return }
            while !Task.isCancelled {
                await connection.loadAccounts()
                if let chatId { await connection.loadAccounts(chatId: chatId) }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}

/// Every account on the Mac, under its agent, with how much is left of each
/// limit and when it resets. Read-only: a conversation is moved to another
/// account from its own Account pill.
struct UsageSheet: View {
    let connection: Connection
    let currentId: String
    @Environment(\.dismiss) private var dismiss

    private let providers: [(id: String, name: String)] =
        [("claude", "Claude"), ("codex", "Codex"), ("antigravity", "Antigravity")]

    var body: some View {
        NavigationStack {
            List {
                if let all = connection.accounts[""] {
                    ForEach(providers, id: \.id) { p in
                        let list = all.accounts(for: p.id)
                        if list.contains(where: { $0.usage != nil || $0.kind != "login" || $0.id == currentId }) {
                            Section {
                                ForEach(list) { row($0) }
                            } header: {
                                HStack(spacing: 6) {
                                    ProviderMark(provider: p.id, size: 13)
                                    Text(p.name)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .refreshable { await connection.loadAccounts() }
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ a: WireAccount) -> some View {
        let now = Date.now
        let limit = a.fullestWindow(now: now)
        let used = limit?.percent
        let blocked = a.isBlocked(now: now)
        let reset = (a.limitedUntil ?? 0) / 1000 > now.timeIntervalSince1970 ? a.limitedUntil : limit?.resetsAt
        let status: String =
            a.needsAuth != nil ? "Needs sign-in"
            : blocked ? "Blocked · " + (reset.map { "resets " + usageResetLabel($0) } ?? "waiting for reset")
            : used.map { "\(max(0, 100 - $0))% left · \(limit!.label)" } ?? "Usage not read yet"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if a.id == currentId {
                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(a.name).superFont(15, weight: .medium).lineLimit(1)
                Spacer()
                Text(status).superFont(12)
                    .foregroundStyle(blocked || a.needsAuth != nil ? Theme.danger : Theme.textSecondary)
                    .lineLimit(1)
            }
            if !a.detail.isEmpty {
                Text(a.detail).superFont(11).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            ForEach(a.liveWindows(now: now), id: \.label) { w in
                HStack(spacing: 8) {
                    Text(w.label).superFont(12).foregroundStyle(Theme.textSecondary)
                        .frame(width: 92, alignment: .leading).lineLimit(1)
                    UsageLeftBar(used: w.percent)
                    Text("\(max(0, 100 - w.percent))% left").superFont(12, weight: .medium)
                        .foregroundStyle(w.percent >= 75 ? usageColour(w.percent) : Theme.textSecondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                    Text(w.resetsAt.map { usageResetLabel($0) } ?? "").superFont(11)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 78, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(Theme.card)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usage-sheet-\(a.id)")
    }
}
