import Testing
import SwiftUI
@testable import SuperAgent

struct AgentNudgeTests {
    private let nudge = "The user hasn't heard from you in a while — say in a few words what you're doing, then continue."

    @Test func theNudgeComesOffTheFront() {
        #expect(AgentNudge.strip(nudge) == "")
        #expect(AgentNudge.strip("\(nudge)\n\nStill building it.") == "Still building it.")
    }

    @Test func everythingElseStays() {
        #expect(AgentNudge.strip("Done.") == "Done.")
        #expect(AgentNudge.strip("Quote: \(nudge)").hasPrefix("Quote:"))
    }
}

/// A round of a loop is shown as one: marked Loop, the instructions the agent
/// gets with it kept out of the conversation.
struct LoopRoundTests {
    @Test func theInstructionsAreSplitOffWhatWasAsked() {
        let round = "polish everything please\n\n(/loop, self-paced: pick your own pace with the loop_wait tool.)"
        let (main, note) = splitLoopNote(round)
        #expect(main == "polish everything please")
        #expect(note == "(/loop, self-paced: pick your own pace with the loop_wait tool.)")
        #expect(splitLoopNote("an ordinary message (with brackets)").note == nil)
    }

    @Test func itIsCalledLoopWithTheIntervalWhenItHasOne() {
        #expect(loopLabel("(/loop, self-paced: pick your own pace…)") == "Loop")
        #expect(loopLabel("(/loop: this repeats on a timer until it is stopped.)") == "Loop")
        #expect(loopLabel("(/loop 5m: run sleep as your last action)") == "Loop · every 5m")
    }
}

/// An option picked from a question goes bare only while the question is the
/// last thing said and the agent is waiting on it.
struct AnswerContextTests {
    @Test func bareWhileTheQuestionIsTheLastWord() {
        #expect(!answerNeedsQuestion(lastMessageId: "a1", questionId: "a1", working: false))
    }

    @Test func withTheQuestionOnceAnythingCameAfterOrTheAgentIsBusy() {
        #expect(answerNeedsQuestion(lastMessageId: "u2", questionId: "a1", working: false))
        #expect(answerNeedsQuestion(lastMessageId: "a2", questionId: "a1", working: false))
        #expect(answerNeedsQuestion(lastMessageId: "a1", questionId: "a1", working: true))
        #expect(answerNeedsQuestion(lastMessageId: nil, questionId: "a1", working: false))
    }
}

/// Picture in picture: where the card rests, and where it settles when let go.
struct MirrorPiPTests {
    private typealias PiP = MirrorPiP<EmptyView>
    private let box = CGSize(width: 390, height: 600)
    private let card = CGSize(width: 184, height: 128)

    @Test func itRestsInsetFromItsCorner() {
        #expect(PiP.rest(.topTrailing, card: card, in: box) == CGPoint(x: 390 - 12 - 92, y: 12 + 64))
        #expect(PiP.rest(.bottomLeading, card: card, in: box) == CGPoint(x: 12 + 92, y: 600 - 12 - 64))
    }

    @Test func itSettlesInTheNearestCorner() {
        #expect(PiP.nearest(CGPoint(x: 40, y: 80), in: box) == .topLeading)
        #expect(PiP.nearest(CGPoint(x: 300, y: 80), in: box) == .topTrailing)
        #expect(PiP.nearest(CGPoint(x: 40, y: 500), in: box) == .bottomLeading)
        #expect(PiP.nearest(CGPoint(x: 300, y: 500), in: box) == .bottomTrailing)
        // Flung far off the screen, it still lands on it.
        #expect(PiP.nearest(CGPoint(x: -500, y: 2000), in: box) == .bottomLeading)
    }

    @Test func aBottomCornerGoesUpForTheKeyboard() {
        #expect(PiP.Corner.bottomLeading.raised == .topLeading)
        #expect(PiP.Corner.bottomTrailing.raised == .topTrailing)
        #expect(PiP.Corner.topTrailing.raised == .topTrailing)
    }
}

/// The pace a reply is shown at while it is written.
struct StreamPaceTests {
    private let text = String(repeating: "The quick brown fox jumps over the lazy dog, twice over. ", count: 40)

    @Test func itMovesOnAndEndsOnAWord() {
        let n = StreamPace.next(shown: 0, target: "hello there, world", dtMs: 33)
        #expect(["hello", "hello there,", "hello there, world"].contains(String("hello there, world".prefix(n))))
    }

    @Test func itQuickensWhenBehindAndNeverLagsFar() {
        let little = StreamPace.next(shown: 0, target: String(text.prefix(40)), dtMs: 33)
        let much = StreamPace.next(shown: 0, target: String(text.prefix(600)), dtMs: 33)
        #expect(much > little)
        #expect(StreamPace.next(shown: 0, target: text, dtMs: 33) > text.count - 900)
    }

    @Test func itGetsThereAndStays() {
        let target = String(text.prefix(500))
        var shown = 0
        var frames = 0
        while shown < 500, frames < 600 {
            shown = StreamPace.next(shown: shown, target: target, dtMs: 33)
            frames += 1
        }
        #expect(shown == 500)
        #expect(frames > 4 && frames < 80)
        #expect(StreamPace.next(shown: 500, target: target, dtMs: 33) == 500)
        #expect(StreamPace.next(shown: 500, target: "short", dtMs: 33) == 5)
    }
}
