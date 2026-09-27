import Testing
@testable import SuperAgent

@Suite struct ModelNameTests {
    @Test func saysTheVersionPeopleKnow() {
        #expect(ModelName.pretty("claude-opus-5-5[1m]") == "Opus 5.5 · 1M context")
        #expect(ModelName.pretty("claude-opus-5-5[1m]", context: false) == "Opus 5.5")
        #expect(ModelName.pretty("claude-sonnet-5") == "Sonnet 5")
        #expect(ModelName.pretty("claude-fable-5-1") == "Fable 5.1")
        #expect(ModelName.pretty("claude-haiku-4-5-20251001") == "Haiku 4.5")
    }

    @Test func leavesOtherModelsAsReported() {
        #expect(ModelName.pretty("gpt-5.5-codex") == "gpt-5.5-codex")
        #expect(ModelName.pretty("") == nil)
    }
}
