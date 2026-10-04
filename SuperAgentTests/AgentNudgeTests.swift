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
