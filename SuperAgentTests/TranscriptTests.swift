import Foundation
import Testing
@testable import SuperAgent

struct MarkdownTests {
    @Test func parsesBlocks() {
        let md = """
        # Title
        Some **bold** text
        and more.

        - one
        - two
        1. first
        2. second

        ```swift
        let x = 1
        ```
        > quoted
        ---
        | a | b |
        |---|---|
        | 1 | 2 |
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Some **bold** text and more."))
        #expect(blocks[2] == .bullets(["one", "two"], ordered: false))
        #expect(blocks[3] == .bullets(["first", "second"], ordered: true))
        #expect(blocks[4] == .code(language: "swift", text: "let x = 1"))
        #expect(blocks[5] == .quote("quoted"))
        #expect(blocks[6] == .rule)
        #expect(blocks[7] == .table(["| a | b |", "| 1 | 2 |"]))
    }

    @Test func unterminatedCodeFenceStillRenders() {
        let blocks = MarkdownParser.parse("Look:\n```\nstill streaming")
        #expect(blocks == [.paragraph("Look:"), .code(language: nil, text: "still streaming")])
    }

    @Test func extractsChoices() {
        let text = """
        Which theme?
        ```ask
        {"question": "Which theme?", "multiple": false, "options": [{"label": "Dark"}, {"label": "Light", "hint": "Default"}]}
        ```
        """
        let (body, choices) = MarkdownParser.extractChoices(text)
        #expect(body == "Which theme?")
        #expect(choices?.options.map(\.label) == ["Dark", "Light"])
        #expect(choices?.options[1].hint == "Default")
        #expect(MarkdownParser.extractChoices("plain").choices == nil)
    }
}

struct TurnTests {
    private func ev(_ seq: Int, _ data: WireEventData) -> WireEvent {
        WireEvent(chatId: "c", seq: seq, ts: Double(1_000 + seq * 1_000), data: data)
    }

    @Test func groupsConsecutiveStepsInsideATurn() {
        let events = [
            ev(1, .user(id: "u", text: "go", images: [], from: .ios, replyTo: nil)),
            ev(2, .session(claudeSessionId: "s", model: nil, commands: [])),
            ev(3, .assistant(id: "a1", text: "Looking.")),
            ev(4, .tool(id: "t1", name: "Bash", detail: "ls", task: nil)),
            ev(5, .toolResult(toolId: "t1", ok: true, summary: "")),
            ev(6, .tool(id: "t2", name: "Read", detail: "a.ts", task: nil)),
            ev(7, .diff(id: "t3", file: "a.ts", hunks: [])),
            ev(8, .assistant(id: "a2", text: "Done.")),
            ev(9, .turnEnd(ok: true, subtype: "success", costUsd: 0.1, tokens: 1234, contextTokens: 41_000))
        ]
        let turns = TurnBuilder.build(events)
        #expect(turns.count == 1)
        let items = turns[0].items
        #expect(items.count == 4) // user, assistant, steps, assistant
        guard case .steps(let g) = items[2] else { Issue.record("steps expected"); return }
        #expect(g.toolCount == 2 && g.editCount == 1)
        #expect(g.summary == "Running · Reading · Editing")
        #expect(turns[0].tokens == 1234)
        #expect(turns[0].duration == 8)
    }

    @Test func verbsAndFailures() {
        #expect(StepGroup.verb(for: "mcp__cove-browser__browser_click") == "Browsing")
        #expect(StepGroup.verb(for: "Write") == "Editing")
        let g = StepGroup(id: "g", events: [
            WireEvent(chatId: "c", seq: 1, ts: 0, data: .tool(id: "t", name: "Bash", detail: "", task: nil)),
            WireEvent(chatId: "c", seq: 2, ts: 0, data: .toolResult(toolId: "t", ok: false, summary: "boom"))
        ])
        #expect(g.failed == 1)
    }
}

struct FixtureFieldTests {
    private final class Marker {}
    @Test func decodesBranchPreviewAndCommands() throws {
        let url = try #require(Bundle(for: Marker.self).url(forResource: "frames", withExtension: "json"))
        struct Frames: Decodable { var server: [ServerFrame]; var events: [WireEvent] }
        let f = try JSONDecoder().decode(Frames.self, from: Data(contentsOf: url))
        guard case let .welcome(_, tree, chats) = f.server[0] else { Issue.record("welcome"); return }
        #expect(tree[0].workspaces[0].branch == "main")
        #expect(tree[0].workspaces[1].isBrowser && tree[0].workspaces[1].host == "en.wikipedia.org")
        #expect(chats[0].preview == "Done — tests pass.")
        guard case let .session(_, _, commands) = f.events[0].data else { Issue.record("session"); return }
        #expect(commands == ["compact", "review"])
    }
}

@Test func outboxRetiredByEcho() throws {
    var t = Transcript()
    t.outbox.append(Outgoing(id: "L-1", chatId: "c1", text: "hi", images: [], ts: 0, model: nil, mode: nil, replyTo: nil))
    t.outbox.append(Outgoing(id: "L-2", chatId: "c1", text: "again", images: [], ts: 0, model: nil, mode: nil, replyTo: nil))
    let echo = try JSONDecoder().decode(WireEvent.self, from: Data(#"{"chatId":"c1","seq":1,"ts":1,"data":{"kind":"user","id":"L-1","text":"hi","from":"ios"}}"#.utf8))
    let applied = t.apply(echo)
    #expect(applied)
    #expect(t.outbox.map(\.id) == ["L-2"])
}

@Test func offlineCacheRoundTrip() throws {
    let id = "test-" + UUID().uuidString.prefix(8)
    defer { OfflineCache.remove(id) }
    let chats = [WireChat(id: "c1", workspaceId: "w1", title: "Hi", updatedAt: 1, live: true, preview: "p")]
    OfflineCache.save(id, "chats", chats)
    // Save writes off-thread; give it a moment.
    var loaded: [WireChat]? = nil
    for _ in 0..<50 {
        loaded = OfflineCache.load(id, "chats", as: [WireChat].self)
        if loaded != nil { break }
        Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(loaded == chats)
    #expect(OfflineCache.load(id, "missing", as: [WireChat].self) == nil)
}
