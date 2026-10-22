import SwiftUI

/// Split view on the iPad, as on the Mac: two to four conversations side by
/// side in the second column. The Mac's rules: a conversation that is in the
/// split is focused by choosing it; any other one leaves the split (one
/// conversation fills the column again). Four is the most the iPad's width
/// holds; two in a narrow window (portrait, Split View) stack instead.
enum IPadSplit {
    static let max = 4

    /// Rows of window indices for this many windows in this much room.
    static func rows(_ n: Int, width: CGFloat) -> [[Int]] {
        switch n {
        case ..<2: return [[0]]
        case 2: return width >= 820 ? [[0, 1]] : [[0], [1]]
        case 3: return width >= 1100 ? [[0, 1, 2]] : [[0, 1], [2]]
        default: return [[0, 1], [2, 3]]
        }
    }
}

/// A window's own navigation, so Files, the board or a file opened from one
/// conversation open in that window, with a Back that returns to it.
struct TileStack<Content: View>: View {
    @State private var path = NavigationPath()
    let content: (Binding<NavigationPath>) -> Content
    var body: some View {
        NavigationStack(path: $path) { content($path) }
    }
}

/// What sits at the leading edge of a window's bar: its number (⌘1–4),
/// blue when it is the window your typing goes to.
struct TileNumber: View {
    let index: Int
    let focused: Bool
    var body: some View {
        Text("\(index + 1)")
            .superFont(11, weight: .bold)
            .foregroundStyle(focused ? Color.white : Theme.textSecondary)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(focused ? Color.accentColor : Theme.border)
            )
            .accessibilityLabel("Window \(index + 1)")
    }
}
