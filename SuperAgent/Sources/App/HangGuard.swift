import UIKit

/// Notices when the app's main thread stops answering, and remembers which
/// conversation was open.
///
/// iOS kills an app whose screen thread is stuck for ten seconds (0x8BADF00D),
/// and a conversation that does it once will do it again every time it is
/// opened — the app could not be used for that chat at all. This watches from a
/// thread of its own: a stall of a few seconds is written down against the open
/// conversation, and the next time that conversation opens it lays out a lot
/// less (see ChatView's safe mode) and says why. Survives the kill: the record
/// is in UserDefaults, written before iOS gets to it.
final class HangGuard: @unchecked Sendable {
    static let shared = HangGuard()
    /// How long the main thread may take to answer before it is a hang.
    static let stall: TimeInterval = 3.5
    /// Hangs older than this are forgotten: the conversation has probably changed.
    static let memory: TimeInterval = 3 * 24 * 3600

    private static let key = "hang.chats"
    private let lock = NSLock()
    private var chatId: String?
    private var foreground = true
    private var running = false

    /// Start watching. Idempotent; call once the app is up.
    @MainActor func start() {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        running = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setForeground(true)
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setForeground(false)
        }
        let t = Thread { [weak self] in self?.watch() }
        t.name = "HangGuard"
        t.qualityOfService = .utility
        t.start()
    }

    private func setForeground(_ on: Bool) {
        lock.lock(); foreground = on; lock.unlock()
    }

    /// The conversation on screen, or nil when none is.
    func setOpen(_ id: String?) {
        lock.lock(); chatId = id; lock.unlock()
    }

    private func watch() {
        var recorded = false
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            lock.lock(); let active = foreground; let open = chatId; lock.unlock()
            guard active else { recorded = false; continue }
            let answered = Atomic()
            DispatchQueue.main.async { answered.set() }
            var waited: TimeInterval = 0
            while !answered.isSet, waited < Self.stall + 0.5 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 0.1
            }
            if answered.isSet { recorded = false; continue }
            if !recorded, let open {
                recorded = true
                Self.record(chat: open)
            }
            // Keep waiting for it, so one long stall is one hang.
            while !answered.isSet { Thread.sleep(forTimeInterval: 0.25) }
        }
    }

    private final class Atomic: @unchecked Sendable {
        private let l = NSLock(); private var on = false
        func set() { l.lock(); on = true; l.unlock() }
        var isSet: Bool { l.lock(); defer { l.unlock() }; return on }
    }

    // MARK: The record

    private static func load() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }

    #if DEBUG
    /// `-hangChat <id>`: that conversation has frozen the app, as far as the app knows.
    static func markForTesting(_ id: String) { record(chat: id) }
    #endif

    private static func record(chat id: String) {
        var all = load()
        let now = Date().timeIntervalSince1970
        all[id] = (all[id] ?? []).filter { now - $0 < memory } + [now]
        UserDefaults.standard.set(all, forKey: key)
    }

    /// How many times this conversation has frozen the app lately.
    static func recentHangs(in chatId: String) -> Int {
        let now = Date().timeIntervalSince1970
        return (load()[chatId] ?? []).filter { now - $0 < memory }.count
    }

    /// Back to laying the whole thing out, on the user's say-so.
    static func forget(_ chatId: String) {
        var all = load()
        all[chatId] = nil
        UserDefaults.standard.set(all, forKey: key)
    }
}
