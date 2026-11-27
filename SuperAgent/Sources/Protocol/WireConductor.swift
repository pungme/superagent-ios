import Foundation

/// A project's Conductor as the Mac sends it (`conductor.get`): its numbered sessions and how Main routes.
struct WireConductorSession: Codable, Hashable, Sendable, Identifiable {
    struct Approval: Codable, Hashable, Sendable { var requestId: String; var preview: String }
    var chatId: String
    var title: String
    var ticket: Int?
    var summary: String
    /// "working", "needs-you", "idle" or "closed".
    var status: String
    var updatedAt: Double
    var approval: Approval?
    var branch: String?
    var unmerged: Int?
    var files: [String]?
    var id: String { chatId }
    /// The tracker's ticket id at the start of the title ("WD-284 Fix header" -> "WD-284"), if any.
    var trackerKey: String? {
        guard let r = title.range(of: #"^\s*[A-Z][A-Z0-9]{1,9}-\d{1,6}\b"#, options: .regularExpression) else { return nil }
        return title[r].trimmingCharacters(in: .whitespaces)
    }
    var titleWithoutKey: String {
        guard let k = trackerKey else { return title }
        let rest = title.replacingOccurrences(of: k, with: "", options: .anchored).trimmingCharacters(in: CharacterSet(charactersIn: " :–-"))
        return rest.isEmpty ? title : rest
    }
}

struct WireConductorState: Codable, Hashable, Sendable {
    var chatId: String
    var routing: String
    var sessions: [WireConductorSession]
}

