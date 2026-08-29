import Foundation

/// What the phone remembers about a Mac between launches: the sidebar, the
/// conversation list and the recent transcript of chats you opened. With the
/// Mac asleep the app still reads; nothing here is ever sent anywhere.
enum OfflineCache {
    private static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("cache", isDirectory: true)
    }()

    /// Events kept per chat; older ones come back from the Mac on demand.
    static let transcriptLimit = 400

    private static func url(_ machineId: String, _ name: String) -> URL {
        root.appendingPathComponent(machineId, isDirectory: true).appendingPathComponent(name + ".json")
    }

    static func load<T: Decodable>(_ machineId: String, _ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url(machineId, name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Encodes and writes off the main thread: a busy turn would otherwise
    /// re-encode the whole transcript between frames.
    static func save<T: Encodable & Sendable>(_ machineId: String, _ name: String, _ value: T) {
        let target = url(machineId, name)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try? data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func removeTranscript(_ machineId: String, chatId: String) {
        try? FileManager.default.removeItem(at: url(machineId, "chat-" + chatId))
    }

    /// Everything about one Mac — for when it's unpaired.
    static func remove(_ machineId: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(machineId, isDirectory: true))
    }
}
