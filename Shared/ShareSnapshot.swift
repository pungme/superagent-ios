import Foundation

/// The share sheet's picture of the world: every paired Mac's projects and
/// chats, written by the app whenever the Mac speaks, read by the extension
/// to draw its picker instantly — even offline, even before any connection.
///
/// A snapshot, deliberately: the extension must never need a round-trip to
/// show the picker. Slightly stale beats a spinner in someone else's app.
/// Compiled into BOTH targets; Foundation only.
enum ShareSnapshot {
    struct Chat: Codable, Identifiable, Hashable {
        var id: String
        var workspaceId: String
        var title: String?
        var updatedAt: Double
    }

    struct Workspace: Codable, Identifiable, Hashable {
        var id: String
        var name: String
    }

    struct Machine: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var workspaces: [Workspace]
        var chats: [Chat]
    }

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.groupId)?
            .appendingPathComponent("share-snapshot.json")
    }

    static func load() -> [Machine] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Machine].self, from: data)) ?? []
    }

    /** Replace one machine's slice, keeping the others. */
    static func update(machine: Machine) {
        guard let url else { return }
        var all = load().filter { $0.id != machine.id }
        all.append(machine)
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func remove(machineId: String) {
        guard let url else { return }
        let rest = load().filter { $0.id != machineId }
        if let data = try? JSONEncoder().encode(rest) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
