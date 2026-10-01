import Testing
import Foundation
@testable import SuperAgent

/// A reply that opens by quoting one of the user's messages is an answer to it.
struct AgentReplyTests {
    private let said = ["make the header sticky", "also why is the build so slow?", "ok ship it"]

    @Test func theQuoteIsLiftedOffTheFront() {
        let r = AgentReply.replyingTo("> also why is the build so slow?\n\nIt rebuilds the image.", userTexts: said)
        #expect(r?.quote == "also why is the build so slow?")
        #expect(r?.rest == "It rebuilds the image.")
    }

    @Test func aShortenedOrDressedUpQuoteStillCounts() {
        #expect(AgentReply.replyingTo("> \"Why is the build so slow…\"\nBecause.", userTexts: said)?.quote == "Why is the build so slow")
        #expect(AgentReply.replyingTo("> make the header\n> sticky\n\nDone.", userTexts: said)?.rest == "Done.")
    }

    @Test func aQuoteOfAnythingElseIsLeftAlone() {
        #expect(AgentReply.replyingTo("> error: ENOENT no such file\n\nThat is the cause.", userTexts: said) == nil)
        #expect(AgentReply.replyingTo("No quote here.", userTexts: said) == nil)
        #expect(AgentReply.replyingTo("First.\n\n> ok ship it\n\nShipped.", userTexts: said) == nil)
    }

    @Test func itNeedsAnAnswerAfterTheQuote() {
        #expect(AgentReply.replyingTo("> ok ship it", userTexts: said) == nil)
        #expect(AgentReply.replyingTo("> a\n\nYes.", userTexts: ["a"]) == nil)
    }
}
