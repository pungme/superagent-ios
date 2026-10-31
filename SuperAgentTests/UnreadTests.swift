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

/// The phone list's "project · status" line: the words come from state the
/// app already has, so these are the rules that turn one into the other.
struct ChatStatusTests {
    private func chat(_ id: String, ws: String = "w1", at: Double = 100, live: Bool = false,
                      preview: String? = "Done.") -> WireChat {
        WireChat(id: id, workspaceId: ws, title: nil, updatedAt: at, live: live, preview: preview)
    }

    private func workspace(_ id: String, _ status: WorkspaceStatus) -> WireWorkspace {
        WireWorkspace(id: id, name: id, path: "/" + id, kind: "app", status: status,
                      branch: nil, browserUrl: nil, subrepos: [])
    }

    @Test func plainWords() {
        #expect(ChatStatus.of(chat("a", live: true), wantsYou: false) == .working)
        #expect(ChatStatus.of(chat("a"), wantsYou: false) == .finished)
        #expect(ChatStatus.of(chat("a", preview: nil), wantsYou: false) == .new)
        // Waiting on an answer is mid-turn on the Mac; it still reads as yours.
        #expect(ChatStatus.of(chat("a", live: true), wantsYou: true) == .wantsYou)
        #expect(ChatStatus.wantsYou.label == "wants you")
    }

    @Test func wantsYouLandsOnTheRunningConversation() {
        let chats = [chat("a", at: 300), chat("b", at: 100, live: true), chat("c", ws: "w2", live: true)]
        let ids = ChatStatus.wantingYou(chats: chats, workspaces: [workspace("w1", .needsYou), workspace("w2", .working)])
        #expect(ids == ["b"])
    }

    @Test func withNothingRunningItIsTheLatest() {
        let chats = [chat("a", at: 300), chat("b", at: 100)]
        #expect(ChatStatus.wantingYou(chats: chats, workspaces: [workspace("w1", .needsYou)]) == ["a"])
        #expect(ChatStatus.wantingYou(chats: chats, workspaces: [workspace("w1", .idle)]).isEmpty)
    }
}
