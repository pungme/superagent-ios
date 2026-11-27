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
}

struct WireConductorState: Codable, Hashable, Sendable {
    var chatId: String
    var routing: String
    var sessions: [WireConductorSession]
}

