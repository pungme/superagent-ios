import Testing
import Foundation
@testable import SuperAgent

/// Who wins when the Mac's composer and this one hold different words.
@MainActor
struct DraftSyncTests {
    @Test func theMacsWordsAreTakenWhenNothingHereIsUnsent() {
        // Opened the chat with an empty field; the Mac has half a sentence.
        #expect(DraftSync.incoming("started on the Mac", local: "", synced: "") == .take("started on the Mac"))
        // Both held the same words; the Mac's moved on.
        #expect(DraftSync.incoming("one two", local: "one", synced: "one") == .take("one two"))
        // The message was sent from the Mac: the field here empties too.
        #expect(DraftSync.incoming("", local: "one two", synced: "one two") == .take(""))
    }

    @Test func wordsTypedHereThatTheMacHasNotHadAreKept() {
        // Mid-sentence, the Mac's older copy arrives.
        #expect(DraftSync.incoming("one", local: "one two th", synced: "one") == .keepAndPush)
        // Written offline, or before drafts were shared at all.
        #expect(DraftSync.incoming("", local: "typed on the train", synced: "") == .keepAndPush)
    }

    @Test func sayingTheSameThingIsNotAChange() {
        #expect(DraftSync.incoming("same", local: "same", synced: "older") == .agree)
        // Only spaces is an empty field, here as on the Mac.
        #expect(DraftSync.incoming("", local: "  \n", synced: "") == .agree)
    }

    @Test func theMacsDraftArrivesAndCountsEachTime() throws {
        let c = Connection(machine: PairedMachine(id: "drafts", name: "Mac", relay: "wss://example.invalid",
                                                  deviceId: "d", secret: Data(repeating: 1, count: 32),
                                                  token: "t", pairedAt: .now))
        let frame = try JSONDecoder().decode(ServerFrame.self, from: Data(#"{"t":"draft","chatId":"c1","text":"hello"}"#.utf8))
        c._applyForTests(frame)
        #expect(c.remoteDrafts["c1"] == .init(text: "hello", n: 1))
        // The same words after a reconnect still register as news.
        c._applyForTests(frame)
        #expect(c.remoteDrafts["c1"] == .init(text: "hello", n: 2))
    }

    @Test func whatTheMacHoldsIsRememberedPerChat() {
        let chat = "draft-test-\(UUID().uuidString)"
        #expect(DraftSync.synced(chat) == "")
        DraftSync.setSynced("abc", chatID: chat)
        #expect(DraftSync.synced(chat) == "abc")
        DraftSync.setSynced("", chatID: chat)
        #expect(DraftSync.synced(chat) == "")
    }
}
