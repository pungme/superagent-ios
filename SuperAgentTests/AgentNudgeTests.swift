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

/// Using the Mac's page from the phone: a finger's place on the picture to a
/// point on the page, and what is sent for it (`browser.input`).
struct PageControlTests {
    private let image = CGSize(width: 700, height: 500)

    @Test("full screen, the page fits whole, centred across, from the top")
    func drawnFit() {
        let r = PageMap.drawn(image: image, in: CGSize(width: 390, height: 700), fitWidth: false)
        #expect(r.minX == 0 && r.minY == 0)
        #expect(abs(r.width - 390) < 0.001)
        #expect(abs(r.height - 390 * 5 / 7) < 0.001)
        // A box wider than the page's shape: centred across.
        let wide = PageMap.drawn(image: image, in: CGSize(width: 1000, height: 250), fitWidth: false)
        #expect(wide.height == 250 && wide.width == 350 && wide.minX == 325)
        // Docked: across the strip, running past its bottom.
        let strip = PageMap.drawn(image: image, in: CGSize(width: 1000, height: 250), fitWidth: true)
        #expect(strip.width == 1000 && strip.minY == 0 && strip.height > 250)
    }

    @Test("a tap lands on the page where it is on the picture, zoomed or not")
    func fraction() {
        let box = CGSize(width: 700, height: 900)
        // At rest the picture is 700×500 at the top: its middle is the page's middle.
        #expect(PageMap.fraction(of: CGPoint(x: 350, y: 250), image: image, box: box, fitWidth: false) == CGPoint(x: 0.5, y: 0.5))
        #expect(PageMap.fraction(of: CGPoint(x: 70, y: 50), image: image, box: box, fitWidth: false) == CGPoint(x: 0.1, y: 0.1))
        // Under the picture: nothing.
        #expect(PageMap.fraction(of: CGPoint(x: 350, y: 700), image: image, box: box, fitWidth: false) == nil)
        // Pinched to twice its size about the box's centre (350, 450): the
        // page's point (0.5, 0.5) is drawn at (350, 50).
        #expect(PageMap.fraction(of: CGPoint(x: 350, y: 50), image: image, box: box, fitWidth: false, zoom: 2) == CGPoint(x: 0.5, y: 0.5))
        // And there and back is the same point.
        let f = CGPoint(x: 0.25, y: 0.75)
        let p = PageMap.point(of: f, image: image, box: box, fitWidth: false, zoom: 2, pan: CGSize(width: 40, height: -30))
        let back = PageMap.fraction(of: p, image: image, box: box, fitWidth: false, zoom: 2, pan: CGSize(width: 40, height: -30))
        #expect(back.map { abs($0.x - f.x) < 1e-9 && abs($0.y - f.y) < 1e-9 } == true)
    }

    @Test("a drag is the same share of the page as it is of the picture")
    func travel() {
        let box = CGSize(width: 350, height: 900)
        // The picture is drawn 350×250: a finger 25 points up is a tenth of the page up.
        let t = PageMap.travel(CGSize(width: 0, height: -25), image: image, box: box, fitWidth: false)
        #expect(t.width == 0 && abs(t.height + 0.1) < 1e-9)
        // Zoomed in twice, the same finger is half as much of the page.
        let z = PageMap.travel(CGSize(width: 0, height: -25), image: image, box: box, fitWidth: false, zoom: 2)
        #expect(abs(z.height + 0.05) < 1e-9)
    }

    @Test("the trackpad: slow is exact, quick goes further, the pointer stays on the page")
    func cursor() {
        #expect(PageMap.gain(speed: 50) == 1)
        #expect(PageMap.gain(speed: 2000) > 3)
        #expect(PageMap.gain(speed: .infinity) == 1)
        let span = CGSize(width: 400, height: 300)
        let slow = PageMap.moveCursor(CGPoint(x: 0.5, y: 0.5), by: CGSize(width: 40, height: 0), speed: 60, span: span)
        #expect(abs(slow.x - 0.6) < 1e-9 && slow.y == 0.5)
        let quick = PageMap.moveCursor(CGPoint(x: 0.5, y: 0.5), by: CGSize(width: 40, height: 0), speed: 1500, span: span)
        #expect(quick.x > 0.7)
        let edge = PageMap.moveCursor(CGPoint(x: 0.95, y: 0.02), by: CGSize(width: 400, height: -400), speed: 60, span: span)
        #expect(edge == CGPoint(x: 1, y: 0))
    }

    @Test("a second tap soon and close is a double-click; late or far, a new click")
    func doubleClick() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let last = (at: CGPoint(x: 0.5, y: 0.5), time: t0)
        #expect(PageMap.isSecondClick(at: CGPoint(x: 0.51, y: 0.5), after: last, now: t0.addingTimeInterval(0.2)))
        #expect(!PageMap.isSecondClick(at: CGPoint(x: 0.51, y: 0.5), after: last, now: t0.addingTimeInterval(0.6)))
        #expect(!PageMap.isSecondClick(at: CGPoint(x: 0.7, y: 0.5), after: last, now: t0.addingTimeInterval(0.2)))
        #expect(!PageMap.isSecondClick(at: CGPoint(x: 0.5, y: 0.5), after: nil))
    }

    @Test("what goes to the Mac is the shape its browser.input takes")
    func wire() throws {
        func json(_ i: BrowserInput) throws -> [String: Any] {
            let data = try JSONEncoder().encode(i.json)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let click = try json(.click(CGPoint(x: 0.25, y: 0.5)))
        #expect(click["type"] as? String == "click" && click["x"] as? Double == 0.25 && click["y"] as? Double == 0.5)
        #expect(click["button"] == nil && click["count"] == nil)
        let right = try json(.click(CGPoint(x: 0.1, y: 0.1), right: true, count: 2))
        #expect(right["button"] as? String == "right" && right["count"] as? Double == 2)
        // Never off the picture, whatever the maths gave: the Mac refuses those.
        let off = try json(.move(CGPoint(x: 1.0000001, y: -0.2)))
        #expect(off["x"] as? Double == 1 && off["y"] as? Double == 0)
        let scroll = try json(.scroll(at: CGPoint(x: 0.5, y: 0.5), delta: CGSize(width: 0, height: -0.25)))
        #expect(scroll["type"] as? String == "scroll" && scroll["dy"] as? Double == -0.25 && scroll["dx"] as? Double == 0)
        let key = try json(.key("Tab", shift: true))
        #expect(key["key"] as? String == "Tab" && key["shift"] as? Bool == true)
        #expect(try json(.text("hé")) ["text"] as? String == "hé")
        #expect(try json(.down(CGPoint(x: 0, y: 0)))["type"] as? String == "down")
        #expect(BrowserInput.keys.contains("Enter") && BrowserInput.keys.contains("ArrowLeft"))
    }
}
