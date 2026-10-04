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
