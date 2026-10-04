import Foundation

/// Claude Code nudges its own agent when a turn has gone quiet — "The user
/// hasn't heard from you in a while — say in a few words what you're doing,
/// then continue." — and the line can come back at the head of the reply. It is
/// the CLI talking to the model, not the agent talking to you. The Mac takes it
/// off what it records; this takes it off the reply while it streams in.
/// Same rule as the desktop's shared/agent-nudge.ts.
enum AgentNudge {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*The user hasn['’]t heard from you in a while\s*[—–-]+\s*say in a few words what you['’]re doing, then continue\.?\s*"#,
        options: [.caseInsensitive])

    static func strip(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = pattern.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else { return text }
        return String(text[r.upperBound...])
    }
}
