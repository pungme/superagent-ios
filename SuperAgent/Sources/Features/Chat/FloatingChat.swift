import SwiftUI

/// The conversation as a stream's chat: the last few messages floating down the
/// right side of the page or simulator, the older ones fading out towards the
/// top. Shown where the full transcript has no room — typing over a mirror on a
/// phone, or the mirror full screen — so what the agent says is still in view.
/// Tapping the messages brings the full conversation back; taps anywhere else
/// go through to what's underneath.
struct FloatingChat: View {
    struct Line: Identifiable, Equatable {
        let id: String
        /// Sent by the person, rather than said by the agent.
        let mine: Bool
        let text: String
    }

    let lines: [Line]
    /// The reply streaming in, if any.
    let live: String?
    /// Room left at the bottom for the mirror's own button row.
    var bottomInset: CGFloat = 10
    /// Room left at the top for the mirror's address bar or title.
    var topInset: CGFloat = 52
    /// Show the full conversation again.
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Spacer(minLength: 0).allowsHitTesting(false)
            messages
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .clipped()
        .padding(.leading, 60)
    }

    private var messages: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(lines) { line in
                bubble(line.text, mine: line.mine)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let live, !live.isEmpty {
                bubble(live, mine: false)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: 320, alignment: .bottom)
        .clipped()
        .animation(.easeOut(duration: 0.2), value: lines)
        // Older lines fade out towards the top, as a stream's chat does.
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Show chat")
        .accessibilityValue(lines.last.map { FloatingChat.plain($0.text) } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("floatingChat")
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(FloatingChat.plain(text))
            .superFont(13)
            .foregroundStyle(.white)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (mine ? Theme.accent.opacity(0.85) : Color.black.opacity(0.6)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .frame(maxWidth: 260, alignment: .trailing)
            .accessibilityHidden(true)
    }

    /// Markdown's marks read as noise at this size; the words are what matter.
    static func plain(_ text: String) -> String {
        var s = splitLoopNote(text).main
        for mark in ["**", "__", "`", "#"] { s = s.replacingOccurrences(of: mark, with: "") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last few things said, the phone's own unsent messages included.
    static func lines(events: [WireEvent], outbox: [Outgoing], limit: Int = 6) -> [Line] {
        var out: [Line] = []
        for e in events.suffix(120) {
            switch e.data {
            case let .user(id, text, _, _, _): out.append(Line(id: id, mine: true, text: text))
            case let .assistant(id, text): out.append(Line(id: id, mine: false, text: text))
            default: break
            }
        }
        let echoed = Set(out.map(\.id))
        for o in outbox where !echoed.contains(o.id) {
            out.append(Line(id: o.id, mine: true, text: o.text))
        }
        return Array(out.filter { !plain($0.text).isEmpty }.suffix(limit))
    }
}
