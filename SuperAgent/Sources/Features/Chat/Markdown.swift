import SwiftUI

/// A small block-level Markdown renderer: headings, paragraphs, lists, fenced
/// code, block quotes, rules and tables (as monospace). Inline styling inside
/// a block is left to AttributedString's Markdown parser. Good enough for what
/// the agent writes; nothing here tries to be CommonMark-complete.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String], ordered: Bool)
    case code(language: String?, text: String)
    case quote(String)
    case rule
    case table([String])
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")[...]
        var paragraph: [String] = []
        func flush() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }
        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while let l = lines.first, !l.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(l); lines = lines.dropFirst()
                }
                if lines.first != nil { lines = lines.dropFirst() } // closing fence
                blocks.append(.code(language: lang.isEmpty ? nil : lang, text: code.joined(separator: "\n")))
                continue
            }
            if trimmed.isEmpty { flush(); continue }
            if let h = heading(trimmed) { flush(); blocks.append(h); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { flush(); blocks.append(.rule); continue }
            if trimmed.hasPrefix(">") {
                flush()
                var quote = [String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)]
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(l.trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); lines = lines.dropFirst()
                }
                blocks.append(.quote(quote.joined(separator: " ")))
                continue
            }
            if trimmed.hasPrefix("|") {
                flush()
                var rows = [trimmed]
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(l.trimmingCharacters(in: .whitespaces)); lines = lines.dropFirst()
                }
                blocks.append(.table(rows.filter { !isTableRule($0) }))
                continue
            }
            if let item = listItem(trimmed) {
                flush()
                var items = [item.text]
                let ordered = item.ordered
                while let l = lines.first {
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if let next = listItem(t), next.ordered == ordered { items.append(next.text); lines = lines.dropFirst() }
                    else if !t.isEmpty, l.hasPrefix("  "), !items.isEmpty { items[items.count - 1] += " " + t; lines = lines.dropFirst() }
                    else { break }
                }
                blocks.append(.bullets(items, ordered: ordered))
                continue
            }
            paragraph.append(trimmed)
        }
        flush()
        return blocks
    }

    private static func heading(_ s: String) -> MarkdownBlock? {
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#", level < 6 { level += 1; idx = s.index(after: idx) }
        guard level > 0, idx < s.endIndex, s[idx] == " " else { return nil }
        return .heading(level: level, text: String(s[idx...]).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ s: String) -> (text: String, ordered: Bool)? {
        if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") { return (String(s.dropFirst(2)), false) }
        if s.hasPrefix("- [ ] ") || s.hasPrefix("- [x] ") { return (String(s.dropFirst(2)), false) }
        var digits = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx].isNumber, digits < 4 { digits += 1; idx = s.index(after: idx) }
        if digits > 0, idx < s.endIndex, s[idx] == ".", s.index(after: idx) < s.endIndex, s[s.index(after: idx)] == " " {
            return (String(s[s.index(idx, offsetBy: 2)...]), true)
        }
        return nil
    }

    private static func isTableRule(_ row: String) -> Bool {
        row.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A ```ask block the desktop renders as buttons: `{question, multiple, options:[{label,hint}]}`.
    struct Choices: Equatable {
        var question: String
        var multiple: Bool
        var options: [(label: String, hint: String?)]
        static func == (a: Choices, b: Choices) -> Bool { a.question == b.question && a.options.map(\.label) == b.options.map(\.label) }
    }

    /// Splits trailing choices out of an assistant message. Returns the text without the block.
    static func extractChoices(_ text: String) -> (text: String, choices: Choices?) {
        guard let range = text.range(of: "```ask", options: .backwards) else { return (text, nil) }
        let after = text[range.upperBound...]
        guard let close = after.range(of: "```") else { return (text, nil) }
        let json = after[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let opts = obj["options"] as? [[String: Any]] else { return (text, nil) }
        let choices = Choices(
            question: obj["question"] as? String ?? "",
            multiple: obj["multiple"] as? Bool ?? false,
            options: opts.compactMap { o in (o["label"] as? String).map { ($0, o["hint"] as? String) } })
        let stripped = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (stripped, choices.options.isEmpty ? nil : choices)
    }
}

// MARK: - Rendering

struct MarkdownView: View {
    let text: String
    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            InlineText(text)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 2)
        case let .paragraph(text):
            InlineText(text)
        case let .bullets(items, ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(i + 1)." : "•")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        InlineText(item)
                    }
                }
            }
        case let .code(language, text):
            CodeBlock(language: language, code: text)
        case let .quote(text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.borderStrong).frame(width: 3)
                InlineText(text).foregroundStyle(Theme.textSecondary)
            }
        case .rule:
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 2)
        case let .table(rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        Text(row.trimmingCharacters(in: CharacterSet(charactersIn: "|")).replacingOccurrences(of: " | ", with: "   "))
                            .font(.system(size: 12, design: .monospaced).weight(i == 0 ? .semibold : .regular))
                    }
                }
            }
        }
    }
}

/// Inline Markdown (bold, italics, code, links) via Foundation's parser.
struct InlineText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        if let a = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(a).textSelection(.enabled)
        } else {
            Text(text).textSelection(.enabled)
        }
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Haptics.tap()
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium)).labelStyle(.titleAndIcon)
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
    }
}
