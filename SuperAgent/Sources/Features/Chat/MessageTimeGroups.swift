import Foundation

/// iMessage-style time clustering: a message shows its timestamp only when
/// the next one is a real pause away (or there is no next one) — sending a
/// follow-up right away retires the previous message's timestamp instead of
/// stamping every single message in a burst. Mirrors desktop's own
/// message-time-groups.ts exactly, same 5-minute threshold, so a
/// conversation reads the same on both.
enum MessageTimeGroups {
    static let gapMs: Double = 5 * 60 * 1000

    /// WireEvent.id of every message (user or assistant) that should show
    /// its own timestamp — the last one in a burst, or one sent alone.
    static func visibleIds(_ events: [WireEvent]) -> Set<String> {
        let msgs = events.filter {
            switch $0.data {
            case .user, .assistant: true
            default: false
            }
        }
        var ids = Set<String>()
        for i in msgs.indices {
            let next = i + 1 < msgs.count ? msgs[i + 1].ts : nil
            if next == nil || next! - msgs[i].ts > gapMs { ids.insert(msgs[i].id) }
        }
        return ids
    }
}

/// A message's own timestamp — "Today 9:41 AM", "Yesterday 9:41 AM", or a
/// short date once it's further back. Mirrors desktop's msgTime() exactly, so
/// the same message reads the same age on both.
func messageTimeLabel(_ date: Date) -> String {
    let time = date.formatted(.dateTime.hour().minute())
    let midnight = Calendar.current.startOfDay(for: Date())
    if date >= midnight { return "Today \(time)" }
    if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: midnight), date >= yesterday {
        return "Yesterday \(time)"
    }
    let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
    let day = date.formatted(sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())
    return day
}
