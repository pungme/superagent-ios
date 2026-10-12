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
struct SimulatorZoomTests {
    @Test("a tap on the zoomed picture is taken back to where it lands at rest")
    func unzoom() {
        let box = CGSize(width: 400, height: 800)
        // No zoom: the point itself.
        #expect(SimulatorMirror.unzoom(CGPoint(x: 100, y: 300), in: box, zoom: 1, pan: .zero) == CGPoint(x: 100, y: 300))
        // Twice the size about the centre: the centre stays, a point halfway out comes halfway back.
        #expect(SimulatorMirror.unzoom(CGPoint(x: 200, y: 400), in: box, zoom: 2, pan: .zero) == CGPoint(x: 200, y: 400))
        #expect(SimulatorMirror.unzoom(CGPoint(x: 300, y: 600), in: box, zoom: 2, pan: .zero) == CGPoint(x: 250, y: 500))
        // Moved 50 to the right: the same spot on the picture is 50 further right in the box.
        #expect(SimulatorMirror.unzoom(CGPoint(x: 350, y: 600), in: box, zoom: 2, pan: CGSize(width: 50, height: 0)) == CGPoint(x: 250, y: 500))
    }

    @Test("the picture is never moved out of the box")
    func clamp() {
        let box = CGSize(width: 400, height: 800)
        #expect(SimulatorMirror.clampPan(CGSize(width: 900, height: -900), in: box, zoom: 2) == CGSize(width: 200, height: -400))
        #expect(SimulatorMirror.clampPan(CGSize(width: 30, height: 30), in: box, zoom: 1) == .zero)
    }
}

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

    @Test func theCardIsTheShapeOfWhatItShows() {
        let fallback = CGSize(width: 200, height: 130)
        // A desktop page, 16:10: wide, its long side across.
        #expect(PiP.cardSize(aspect: 1.6, fallback: fallback) == CGSize(width: 200, height: 125))
        // A page in a wide pane: wider still, never taller for it.
        #expect(PiP.cardSize(aspect: 1.75, fallback: fallback) == CGSize(width: 200, height: 114))
        // A phone's screen: tall.
        let phone = PiP.cardSize(aspect: 1206.0 / 2622.0, fallback: fallback)
        #expect(phone.height == 230 && phone.width == 106)
        // Absurd proportions are held to something that can be tapped.
        #expect(PiP.cardSize(aspect: 9, fallback: fallback).height >= 83)
        #expect(PiP.cardSize(aspect: 0.05, fallback: fallback).width >= 96)
        // Nothing to go on yet.
        #expect(PiP.cardSize(aspect: nil, fallback: fallback) == fallback)
        #expect(PiP.cardSize(aspect: 0, fallback: fallback) == fallback)
    }

    @Test("pinched bigger it keeps its shape, from as it comes to two and a half times")
    func pinched() {
        let card = CGSize(width: 200, height: 125)
        #expect(PiP.enlarged(card, times: 1) == card)
        #expect(PiP.enlarged(card, times: 1.5) == CGSize(width: 300, height: 188))
        // Never smaller than it comes, never past two and a half times.
        #expect(PiP.enlarged(card, times: 0.4) == card)
        #expect(PiP.enlarged(card, times: 9) == CGSize(width: 500, height: 313))
        #expect(PiP.clampedScale(.nan) == 1)
        #expect(PiP.clampedScale(.infinity) == 1)
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

    @Test func aBurstThatEndsMidWordIsHeldToItsLastWholeWord() {
        #expect(StreamPace.wholeWords("The header was the pro", open: true) == 19)
        #expect(StreamPace.wholeWords("The header was the pro", open: false) == 22)
        #expect(StreamPace.wholeWords("Th", open: true) == 0)
        #expect(StreamPace.next(shown: 0, target: "The header was the pro", dtMs: 5000, open: true) == 19)
        #expect(StreamPace.next(shown: 19, target: "The header was the problem. ", dtMs: 5000, open: true) == 28)
        #expect(StreamPace.next(shown: 19, target: "The header was the pro", dtMs: 5000, open: false) == 22)
        #expect(StreamPace.next(shown: 22, target: "The header was the pro", dtMs: 33, open: true) == 22)
    }
}
