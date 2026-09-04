import Foundation
import SwiftUI
import Testing
@testable import SuperAgent

/// Unread is the only state the phone keeps that the Mac never sees, so it has
/// no wire fixture to check it against — these are the rules themselves.
struct UnreadTests {
    private func chat(_ id: String, _ updatedAt: Double) -> WireChat {
        WireChat(id: id, workspaceId: "w1", title: nil, updatedAt: updatedAt, live: false)
    }

    /// A fresh machine id per test: the store is backed by UserDefaults, and
    /// tests must not read each other's leftovers.
    private func store() -> Unread { Unread(machineId: "test-" + UUID().uuidString) }

    @Test func nothingIsUnreadOnFirstSight() {
        let u = store()
        let chats = [chat("a", 100), chat("b", 200)]
        u.note(chats)
        #expect(chats.allSatisfy { !u.isUnread($0) })
        #expect(!u.any(in: chats))
    }

    @Test func aConversationThatMovesGoesUnread() {
        let u = store()
        u.note([chat("a", 100)])
        #expect(u.isUnread(chat("a", 101)))
        #expect(u.any(in: [chat("a", 101)]))
    }

    @Test func readingItClearsIt() {
        let u = store()
        u.note([chat("a", 100)])
        let moved = chat("a", 101)
        #expect(u.isUnread(moved))
        u.markSeen(moved)
        #expect(!u.isUnread(moved))
        // And a later reply marks it again.
        #expect(u.isUnread(chat("a", 102)))
    }

    /// note() must never quietly mark a waiting conversation as read: chat
    /// lists arrive constantly, and one that arrived while you were elsewhere
    /// would clear itself before you ever saw the dot.
    @Test func aLaterListDoesNotClearWhatIsWaiting() {
        let u = store()
        u.note([chat("a", 100)])
        u.note([chat("a", 101)])
        #expect(u.isUnread(chat("a", 101)))
    }

    @Test func deletedConversationsStopTakingSpace() {
        let u = store()
        u.note([chat("a", 100), chat("b", 100)])
        u.note([chat("b", 100)])
        // "a" is gone, so it is a stranger again rather than a stale record.
        #expect(!u.isUnread(chat("a", 999)))
    }

    /// The dot survives being put down and picked up: it is written through to
    /// UserDefaults, not held in memory for the life of one launch.
    @Test func itRemembersAcrossLaunches() {
        let id = "test-" + UUID().uuidString
        let first = Unread(machineId: id)
        first.note([chat("a", 100)])
        let second = Unread(machineId: id)
        #expect(second.isUnread(chat("a", 101)))
        #expect(!second.isUnread(chat("a", 100)))
    }
}

/// UISearchBar's reserved icon/clear-button width leaves no room to lay out
/// "Search every conversation" at .xxLarge and up, so it renders no
/// placeholder at all rather than truncating — see SidebarView.searchPrompt.
struct SidebarSearchPromptTests {
    @Test func fullPromptAtOrdinarySizes() {
        for size: DynamicTypeSize in [.xSmall, .medium, .large, .xLarge] {
            #expect(SidebarView.searchPrompt(for: size) == "Search every conversation")
        }
    }

    @Test func shortPromptOnceTooNarrow() {
        for size: DynamicTypeSize in [.xxLarge, .xxxLarge, .accessibility1, .accessibility5] {
            #expect(SidebarView.searchPrompt(for: size) == "Search")
        }
    }
}
