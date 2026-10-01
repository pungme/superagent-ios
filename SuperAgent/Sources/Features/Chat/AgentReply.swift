import Foundation

/// An agent's reply that answers one message in particular.
///
/// The agent opens such a reply by quoting the message it answers, as a
/// Markdown blockquote on the first line (the Mac's prompt asks it to). Here
/// that quote is lifted out and drawn the way a messaging app draws a reply:
/// the message in a chip above the answer. Only when the quote really is
/// something the user said — an agent also opens with a blockquote to cite a
/// log line, and that is not a reply. The same rule as the Mac's
/// (shared/reply-quote.ts).
enum AgentReply {
    private static func tidy(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*_ "))
        if out.hasSuffix("…") { out.removeLast() } else if out.hasSuffix("...") { out.removeLast(3) }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The blockquote a text opens with, and what follows it.
    static func splitLeadingQuote(_ text: String) -> (quote: String, rest: String)? {
        var lines = text.components(separatedBy: "\n")[...]
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines = lines.dropFirst() }
        var quoted: [String] = []
        while let line = lines.first {
            let trimmed = line.drop { $0 == " " }
            guard line.count - trimmed.count <= 3, trimmed.hasPrefix(">") else { break }
            var body = trimmed.dropFirst()
            if body.hasPrefix(" ") { body = body.dropFirst() }
            quoted.append(String(body))
            lines = lines.dropFirst()
        }
        guard !quoted.isEmpty else { return nil }
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines = lines.dropFirst() }
        let quote = tidy(quoted.joined(separator: " "))
        let rest = lines.joined(separator: "\n")
        guard !quote.isEmpty, !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (quote, rest)
    }

    /// The user's message this reply opens by quoting, and the reply's own
    /// text — nil when it does not open with one of the user's messages.
    static func replyingTo(_ text: String, userTexts: [String]) -> (quote: String, rest: String)? {
        guard let lead = splitLeadingQuote(text), lead.quote.count >= 2 else { return nil }
        let needle = lead.quote.lowercased()
        return userTexts.contains { tidy($0).lowercased().contains(needle) } ? lead : nil
    }
}
