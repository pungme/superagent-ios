import Foundation

/// A model id as people say it: "claude-opus-5-5[1m]" → "Opus 5.5 · 1M context".
enum ModelName {
    static func pretty(_ id: String) -> String? { pretty(id, context: true) }

    static func pretty(_ id: String, context: Bool) -> String? {
        let raw = id.lowercased()
        let oneM = raw.contains("[1m]")
        let base = raw.replacingOccurrences(of: "[1m]", with: "")
        // claude-<family>-<major>[-<minor>][-<yyyymmdd>]
        guard let m = base.wholeMatch(of: /claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?/) else {
            // Codex and anything else: show it as reported.
            return id.isEmpty ? nil : id
        }
        let family = m.1.prefix(1).uppercased() + m.1.dropFirst()
        let version = m.3.map { "\(m.2).\($0)" } ?? String(m.2)
        return "\(family) \(version)" + (context && oneM ? " · 1M context" : "")
    }
}
