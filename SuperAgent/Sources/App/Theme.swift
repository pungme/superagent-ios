import SwiftUI
import UIKit

/// SuperAgent's palette, lifted from the desktop's main.css so both feel like
/// one product: warm-white surfaces, near-black accents, quiet greys; the dark
/// theme is the desktop's #1e1f24 world, not a naive inversion.
enum Theme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Page background (desktop --bg-content).
    static let content = dynamic(light: UIColor(white: 1, alpha: 1), dark: UIColor(red: 0.118, green: 0.122, blue: 0.141, alpha: 1))
    /// Sidebar / grouped background (desktop --bg-panel).
    static let panel = dynamic(light: UIColor(red: 0.965, green: 0.965, blue: 0.973, alpha: 1), dark: UIColor(red: 0.149, green: 0.153, blue: 0.18, alpha: 1))
    /// Cards on the panel (desktop --group-card).
    static let card = dynamic(light: .white, dark: UIColor(white: 1, alpha: 0.05))
    static let border = dynamic(light: UIColor(white: 0, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.08))
    static let borderStrong = dynamic(light: UIColor(white: 0, alpha: 0.13), dark: UIColor(white: 1, alpha: 0.14))
    static let textPrimary = dynamic(light: UIColor(white: 0, alpha: 0.85), dark: UIColor(white: 1, alpha: 0.86))
    static let textSecondary = dynamic(light: UIColor(white: 0, alpha: 0.5), dark: UIColor(white: 1, alpha: 0.5))
    static let textTertiary = dynamic(light: UIColor(white: 0, alpha: 0.36), dark: UIColor(white: 1, alpha: 0.32))
    /// The accent: near-black on light, off-white on dark (desktop --accent). User bubbles.
    static let accent = dynamic(light: UIColor(red: 0.09, green: 0.094, blue: 0.114, alpha: 1), dark: UIColor(red: 0.941, green: 0.941, blue: 0.949, alpha: 1))
    static let accentFg = dynamic(light: .white, dark: UIColor(red: 0.09, green: 0.094, blue: 0.114, alpha: 1))
    static let accentSoft = dynamic(light: UIColor(white: 0, alpha: 0.07), dark: UIColor(white: 1, alpha: 0.14))
    /// Assistant bubble (desktop --assistant-bubble).
    static let assistantBubble = dynamic(light: UIColor(white: 0, alpha: 0.045), dark: UIColor(white: 1, alpha: 0.06))
    static let hover = dynamic(light: UIColor(white: 0, alpha: 0.05), dark: UIColor(white: 1, alpha: 0.07))
    static let codeBackground = dynamic(light: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1), dark: UIColor(white: 0, alpha: 0.28))

    // Status — the same three as the desktop sidebar.
    static let working = Color(red: 0.243, green: 0.812, blue: 0.557)   // #3ecf8e
    static let needsYou = Color(red: 0.941, green: 0.706, blue: 0.161)  // #f0b429
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let added = Color(red: 0.24, green: 0.72, blue: 0.45)
    static let removed = Color(red: 0.9, green: 0.35, blue: 0.35)

    static let bubbleRadius: CGFloat = 18
    static let cardRadius: CGFloat = 12
}

extension View {
    /// Standard card on the panel background.
    func superCard() -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
    }
}

/// The small uppercase group label the desktop sidebar uses.
struct GroupLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// `⎇ main` — the branch chip from the sidebar.
struct BranchChip: View {
    let branch: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .semibold))
            Text(branch).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.accentSoft, in: Capsule())
    }
}

/// Spinner while working, amber dot when it needs you, faint dot when idle.
struct StatusIndicator: View {
    let status: WorkspaceStatus
    var body: some View {
        Group {
            switch status {
            case .working: ProgressView().controlSize(.mini).tint(Theme.working)
            case .needsYou: Circle().fill(Theme.needsYou).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Theme.needsYou.opacity(0.35), lineWidth: 3))
            case .idle: Circle().fill(Theme.textTertiary.opacity(0.6)).frame(width: 6, height: 6)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(Text(status == .needsYou ? "needs you" : status.rawValue))
    }
}

/// A small pill button like the desktop's Model / Mode controls.
struct ControlPill<Label: View>: View {
    let label: () -> Label
    var body: some View {
        label()
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().stroke(Theme.border))
    }
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
