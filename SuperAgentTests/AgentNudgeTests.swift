import Testing
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
