import SwiftUI
import UIKit

/// Superagent's palette, lifted from the desktop's main.css so both feel like
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
    /// The accent choices, shared with the desktop's palette so a person using
    /// both sees the same pink. 'standard' is the monochrome default below.
    enum Accent: String, CaseIterable {
        case standard, pink, violet, blue, teal, green, amber

        /// The chosen colour, or nil for the monochrome default.
        var colour: UIColor? {
            switch self {
            case .standard: nil
            case .pink: UIColor(red: 0.878, green: 0.337, blue: 0.549, alpha: 1)
            case .violet: UIColor(red: 0.486, green: 0.424, blue: 0.941, alpha: 1)
            case .blue: UIColor(red: 0.239, green: 0.51, blue: 0.91, alpha: 1)
            case .teal: UIColor(red: 0.071, green: 0.647, blue: 0.58, alpha: 1)
            case .green: UIColor(red: 0.247, green: 0.631, blue: 0.388, alpha: 1)
            case .amber: UIColor(red: 0.847, green: 0.529, blue: 0.227, alpha: 1)
            }
        }

        /// The bundled alternate icon carrying this colour; nil = the shipped icon.
        var iconName: String? {
            self == .standard ? nil : "AppIcon" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    static var chosenAccent: Accent {
        Accent(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .standard
    }

    /// The accent: near-black on light, off-white on dark (desktop --accent) —
    /// or the user's chosen colour, same in both themes. User bubbles.
    ///
    /// Computed rather than stored so a change takes effect on the next render;
    /// the root view re-identifies itself when the choice changes (see
    /// SuperAgentApp), which is what makes "next render" mean "now".
    static var accent: Color {
        if let c = chosenAccent.colour { return Color(c) }
        return dynamic(light: UIColor(red: 0.09, green: 0.094, blue: 0.114, alpha: 1), dark: UIColor(red: 0.941, green: 0.941, blue: 0.949, alpha: 1))
    }
    static var accentFg: Color {
        chosenAccent == .standard
            ? dynamic(light: .white, dark: UIColor(red: 0.09, green: 0.094, blue: 0.114, alpha: 1))
            : .white
    }
    static var accentSoft: Color {
        if let c = chosenAccent.colour { return Color(c.withAlphaComponent(0.16)) }
        return dynamic(light: UIColor(white: 0, alpha: 0.07), dark: UIColor(white: 1, alpha: 0.14))
    }
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

/// The desktop's type sizes, but scaling. SwiftUI's `.system(size:)` is fixed by
/// design — `relativeTo:` exists only for custom fonts — so the size is scaled
/// here against the text style nearest it and handed back as a plain system font.
/// Reading `dynamicTypeSize` from the environment is what makes a view redraw
/// when Larger Text moves; an ambient `UITraitCollection.current` would not.
private struct ScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let monospacedDigit: Bool

    /// `ViewModifier` is a main-actor protocol, which would make both this
    /// initialiser and `superFont` main-actor too — and they are called from
    /// plain escaping label closures (`PhotosPicker`, `Button`) that are not.
    nonisolated init(size: CGFloat, weight: Font.Weight, design: Font.Design, monospacedDigit: Bool) {
        self.size = size
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        let traits = UITraitCollection { $0.preferredContentSizeCategory = Self.category(for: typeSize) }
        let scaled = UIFontMetrics(forTextStyle: Self.style(for: size)).scaledValue(for: size, compatibleWith: traits)
        let font = Font.system(size: scaled, weight: weight, design: design)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }

    /// The style whose default size is nearest, so each size grows on the curve
    /// meant for text of its own rank — captions stretch less than titles do.
    private static func style(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<11.5: .caption2      // 11
        case ..<12.75: .caption1     // 12
        case ..<14: .footnote        // 13
        case ..<15.75: .subheadline  // 15
        case ..<16.5: .callout       // 16
        case ..<19: .body            // 17
        case ..<21: .title3          // 20
        case ..<25: .title2          // 22
        case ..<31: .title1          // 28
        default: .largeTitle         // 34
        }
    }

    private static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

extension View {
    /// `.superFont(13, weight: .semibold)` — the desktop's 13 pt at the default
    /// text size, scaling from there. Clamp a row too cramped to grow with
    /// `.dynamicTypeSize(...(.accessibility2))`; it flows into this.
    nonisolated func superFont(_ size: CGFloat, weight: Font.Weight = .regular,
                               design: Font.Design = .default, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, monospacedDigit: monospacedDigit))
    }
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
            .superFont(11, weight: .semibold)
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// `⎇ main` — the branch chip from the sidebar.
struct BranchChip: View {
    let branch: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").superFont(9, weight: .semibold)
            Text(branch).superFont(11, weight: .medium).lineLimit(1)
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
            .superFont(12, weight: .medium)
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
