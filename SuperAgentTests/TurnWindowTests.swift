import Testing
import Foundation
@testable import SuperAgent

/// How much of a conversation is laid out. The transcript is a non-lazy stack,
/// so what is in the window is what every layout pass pays for, and iOS makes
/// several passes when the app is put away. A real working session is two or
/// three turns holding 110 000 characters, so the cut has to fall inside a turn.
struct TurnWindowTests {
    private func events(turns: Int, repliesPerTurn: Int, chars: Int) -> [WireEvent] {
        var out: [WireEvent] = []
        var seq = 0
        for t in 0..<turns {
            seq += 1
            out.append(WireEvent(chatId: "c", seq: seq, ts: Double(seq),
                                 data: .user(id: "u\(t)", text: "ask \(t)", images: [], from: .ios, replyTo: nil)))
            for r in 0..<repliesPerTurn {
                seq += 1
                out.append(WireEvent(chatId: "c", seq: seq, ts: Double(seq),
                                     data: .assistant(id: "a\(t)-\(r)", text: String(repeating: "x", count: chars))))
            }
        }
        return out
    }

    @Test func aSingleHugeTurnIsCutInsideItself() {
        let turns = TurnBuilder.build(events(turns: 2, repliesPerTurn: 40, chars: 2_000))
        let w = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8)
        let shown = w.turns.reduce(0) { $0 + $1.items.count }
        #expect(shown < 12, "about the budget's worth of rows, not 80 replies (shown \(shown))")
        #expect(shown >= 8)
        #expect(w.hidden == turns.reduce(0) { $0 + $1.items.count } - shown)
        // The newest row is always the last one shown.
        #expect(w.turns.last?.items.last?.id == turns.last?.items.last?.id)
    }

    @Test func aShortConversationShowsEverything() {
        let turns = TurnBuilder.build(events(turns: 3, repliesPerTurn: 2, chars: 100))
        let w = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8)
        #expect(w.hidden == 0)
        #expect(w.turns == turns)
    }

    @Test func theLeastItemsShowWhateverTheyWeigh() {
        let turns = TurnBuilder.build(events(turns: 1, repliesPerTurn: 20, chars: 50_000))
        let w = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8)
        #expect(w.turns.reduce(0) { $0 + $1.items.count } == 8)
    }

    @Test func aTableWeighsMoreThanProseOfTheSameLength() {
        let prose = String(repeating: "a", count: 300)
        let table = String(repeating: "| a | b |\n", count: 30)
        #expect(table.utf8.count <= prose.utf8.count + 10)
        #expect(TurnItem.textWeight(table) > TurnItem.textWeight(prose) * 3 / 2)
    }

    @Test func theFloorKeepsWhatTheReaderWasLookingAt() {
        let turns = TurnBuilder.build(events(turns: 1, repliesPerTurn: 40, chars: 2_000))
        let plain = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8)
        let floorId = turns[0].items[10].id
        let kept = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8, floor: floorId)
        #expect(kept.turns.first?.items.first?.id == floorId)
        #expect(kept.hidden < plain.hidden)
        // A floor already inside the window changes nothing.
        let inside = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8,
                                        floor: plain.firstItemId)
        #expect(inside.hidden == plain.hidden)
    }

    @Test func moreBudgetShowsMore() {
        let turns = TurnBuilder.build(events(turns: 2, repliesPerTurn: 40, chars: 2_000))
        let a = TurnWindow.visible(turns, maxTurns: 30, budget: 8_000, leastItems: 8)
        let b = TurnWindow.visible(turns, maxTurns: 50, budget: 16_000, leastItems: 8)
        #expect(b.hidden < a.hidden)
    }
}
