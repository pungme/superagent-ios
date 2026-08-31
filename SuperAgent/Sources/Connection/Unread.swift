import Foundation
import Observation

/// What you have already read, per Mac, kept on this phone.
///
/// The desktop keeps unread in the window's memory: a conversation goes unread
/// when a turn finishes while you are not looking at it, and clears when you
/// open it. The phone cannot borrow that. It is a second pair of eyes on the
/// same conversations, and what the Mac has seen says nothing about what you
/// have — the whole point of carrying it is to find out what happened while you
/// were somewhere else. So this is local, and it is the only state in the app
/// the Mac neither knows nor needs to.
///
/// A conversation is unread when it has moved since you last had it open.
/// Anything the phone has never seen before is recorded as read on sight, so
/// pairing a Mac with two hundred old conversations does not light every row.
@Observable
final class Unread {
    private let key: String
    /// chatId → the updatedAt you were last looking at.
    private var seen: [String: Double]

    init(machineId: String) {
        key = "seen:" + machineId
        seen = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    func isUnread(_ chat: WireChat) -> Bool {
        guard let s = seen[chat.id] else { return false }
        return chat.updatedAt > s
    }

    /// Any conversation in this project waiting to be read.
    func any(in chats: [WireChat]) -> Bool { chats.contains(where: isUnread) }

    /// You are looking at it now, so it is read up to here.
    func markSeen(_ chat: WireChat) { record(chat.id, chat.updatedAt) }

    /// A fresh chat list from the Mac. Conversations this phone has not met are
    /// recorded as read where they stand; ones that are gone stop taking space.
    func note(_ chats: [WireChat]) {
        var next = seen
        for c in chats where next[c.id] == nil { next[c.id] = c.updatedAt }
        let live = Set(chats.map(\.id))
        next = next.filter { live.contains($0.key) }
        if next != seen { seen = next; save() }
    }

    private func record(_ chatId: String, _ at: Double) {
        guard seen[chatId] != at else { return }
        seen[chatId] = at
        save()
    }

    private func save() { UserDefaults.standard.set(seen, forKey: key) }
}
