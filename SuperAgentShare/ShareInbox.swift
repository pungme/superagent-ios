import Foundation

/// Where a share lands before anyone decides what to do with it.
///
/// The share extension writes here and knows nothing else — no relay, no
/// chats, no network. The app reads it when it next comes forward and asks
/// the user where the item should go. Items survive until they are used or
/// deleted, so "share now, decide in another session later" is the normal
/// path, not a special case.
///
/// This file is compiled into BOTH the app and the extension; keep it free
/// of anything but Foundation.
enum ShareInbox {
    /// Must match the app-group in both targets' entitlements.
    static let groupId = "group.dev.pungme.superagent.ios"

    struct Item: Codable, Identifiable, Hashable {
        var id: String
        /// The shared words: a URL as its absolute string, or the text itself.
        var text: String
        /// File name (inside the inbox directory) of the shared image, if any.
        var imageFile: String?
        var ts: Double
    }

    static var dir: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("inbox", isDirectory: true)
    }

    static func save(text: String, imageData: Data? = nil) {
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID().uuidString
        var item = Item(id: id, text: text, imageFile: nil, ts: Date().timeIntervalSince1970)
        if let imageData {
            let name = id + ".img"
            do {
                try imageData.write(to: dir.appendingPathComponent(name))
                item.imageFile = name
            } catch {
                // The words still go through; the picture is best-effort.
            }
        }
        if let data = try? JSONEncoder().encode(item) {
            try? data.write(to: dir.appendingPathComponent(id + ".json"))
        }
    }

    static func items() -> [Item] {
        guard let dir,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { name -> Item? in
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
                return try? JSONDecoder().decode(Item.self, from: data)
            }
            .sorted { $0.ts < $1.ts }
    }

    static func imageData(_ item: Item) -> Data? {
        guard let dir, let file = item.imageFile else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(file))
    }

    static func remove(_ item: Item) {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.id + ".json"))
        if let file = item.imageFile {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }
}
