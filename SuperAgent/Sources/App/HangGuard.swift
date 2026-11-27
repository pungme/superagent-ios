import Darwin
import UIKit
import MetricKit

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
    /// How long the main thread may take to answer before the first look at where it is.
    static let firstLook: TimeInterval = 1.5
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
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(false, forKey: Self.runningKey)
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(true, forKey: Self.runningKey)
        }
        // Still marked as on screen from last time: it ended without going to
        // the background first, a crash or the watchdog. Write that down.
        if Self.lastRunEndedOnScreen {
            PhoneDiagnostics.saveExit(lastChat: UserDefaults.standard.string(forKey: Self.lastChatKey))
        }
        UserDefaults.standard.set(true, forKey: Self.runningKey)
        MXMetricManager.shared.add(MetricKitSink.shared)
        Connection.trail = { [weak self] in self?.mark($0) }
        Connection.pendingDiagnostics = { PhoneDiagnostics.pending() }
        Connection.removeDiagnostic = { PhoneDiagnostics.remove($0) }
        Connection.markDiagnosticSent = { PhoneDiagnostics.markSent($0) }
        StackSampler.start()
        let t = Thread { [weak self] in self?.watch() }
        t.name = "HangGuard"
        t.qualityOfService = .utility
        t.start()
    }

    private func setForeground(_ on: Bool) {
        lock.lock(); foreground = on; lock.unlock()
    }

    static let runningKey = "hang.running"
    /// The last run ended while on screen (a crash, or iOS killing it frozen).
    /// Read once, before start() marks this run as running.
    static let lastRunEndedOnScreen: Bool = UserDefaults.standard.bool(forKey: runningKey)
    static let lastChatKey = "hang.lastChat"

    /// The conversation on screen, or nil when none is.
    func setOpen(_ id: String?) {
        UserDefaults.standard.set(id, forKey: Self.lastChatKey)
        lock.lock(); chatId = id; lock.unlock()
    }

    private func watch() {
        var recorded = false
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            lock.lock(); let active = foreground; let open = chatId; lock.unlock()
            guard active else { recorded = false; continue }
            let answered = Atomic()
            let sent = Date()
            DispatchQueue.main.async { answered.set() }
            // Wall-clock, not counted sleeps: a short sleep on this thread oversleeps (it runs at
            // utility priority), and counting 0.05 s a turn made "3.5 s" take ten real seconds
            // on a busy phone, which is past the point iOS kills the app.
            while !answered.isSet, Date().timeIntervalSince(sent) < Self.firstLook {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if answered.isSet {
                recorded = false
                let took = Date().timeIntervalSince(sent)
                if took >= Self.logAt { PhoneDiagnostics.saveHang(seconds: took, snapshot: snapshot()) }
                continue
            }
            // What was on screen while it is stuck, not after it recovers, and
            // written now: past ten seconds iOS kills the app (0x8BADF00D) and
            // nothing after this line would run.
            var during = snapshot()
            during["ongoing"] = true
            var provisional = PhoneDiagnostics.saveHang(seconds: Date().timeIntervalSince(sent), snapshot: during)
            // Where the main thread actually is, a few times while it stays stuck: the report
            // showed how big the chat was and never what the app was doing.
            var stacks: [[String]] = []
            var nextSample: TimeInterval = 0
            // Keep waiting for it, so one long stall is one hang.
            while !answered.isSet {
                Thread.sleep(forTimeInterval: 0.25)
                let elapsed = Date().timeIntervalSince(sent)
                // Past the stall point the conversation counts as frozen (safe mode next time).
                if !recorded, elapsed >= Self.stall, let open {
                    recorded = true
                    Self.record(chat: open)
                }
                if elapsed >= nextSample, stacks.count < 6, !answered.isSet {
                    stacks.append(StackSampler.sample())
                    nextSample = elapsed + 1.2
                    during["stacks"] = stacks
                    let again = PhoneDiagnostics.saveHang(seconds: elapsed, snapshot: during)
                    if let provisional { PhoneDiagnostics.remove(provisional) }
                    provisional = again
                }
            }
            if let provisional { PhoneDiagnostics.remove(provisional) }
            during["ongoing"] = nil
            PhoneDiagnostics.saveHang(seconds: Date().timeIntervalSince(sent), snapshot: during)
        }
    }

    // MARK: What was going on (written to the freeze log, see PhoneDiagnostics)

    /// A stall this long is written down for the Mac, short of the 3.5 s that
    /// puts a conversation in safe mode: under a second already feels frozen.
    static let logAt: TimeInterval = 0.75
    private var context: [String: String] = [:]
    private var trail: [String] = []

    /// Facts about what is on screen (the open chat's size, its longest text).
    func note(_ key: String, _ value: String) {
        lock.lock(); context[key] = value; lock.unlock()
    }

    /// The last things the main thread did, newest last.
    func mark(_ what: String) {
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        lock.lock()
        trail.append("\(stamp) \(what)")
        if trail.count > 40 { trail.removeFirst(trail.count - 40) }
        lock.unlock()
    }

    /// What is going on right now, for Copy Report: the open chat, what is on
    /// screen and the last 40 things the app did, even when nothing froze the
    /// main thread (a screen waiting on a connection looks just as stuck).
    func live() -> String {
        var now = snapshot()
        now["at"] = ISO8601DateFormatter().string(from: Date())
        guard let d = try? JSONSerialization.data(withJSONObject: now, options: [.sortedKeys, .prettyPrinted]) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    private func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["chat": chatId ?? "", "context": context, "trail": trail]
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


/// Apple's own hang reports, with the main thread's call stack: MetricKit hands
/// them to the app (on the next launch at the latest), and they wait in the
/// freeze log for the Mac.
final class MetricKitSink: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitSink()
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            PhoneDiagnostics.save(kind: "metrickit", id: UUID().uuidString, body: p.jsonRepresentation())
        }
    }
}

/// The freeze log: what the phone noticed about its own stalls, kept on disk
/// until the Mac has taken it (Connection.uploadDiagnostics). A freeze under
/// iOS's ten-second watchdog leaves no report anywhere else.
enum PhoneDiagnostics {
    static let keep = 60

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @discardableResult
    static func saveHang(seconds: TimeInterval, snapshot: [String: Any]) -> URL? {
        var body = snapshot
        body["seconds"] = (seconds * 100).rounded() / 100
        body["at"] = ISO8601DateFormatter().string(from: Date())
        body["app"] = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        var size = utsname(); uname(&size)
        body["device"] = withUnsafeBytes(of: &size.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        body["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return nil }
        return save(kind: "hang", id: UUID().uuidString, body: data)
    }

    /// The app ended while on screen (a crash, or iOS killing a frozen app).
    static func saveExit(lastChat: String?) {
        let body: [String: Any] = [
            "what": "Superagent ended while it was on screen: a crash, or iOS stopping it for not responding.",
            "chat": lastChat ?? "", "at": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        save(kind: "exit", id: UUID().uuidString, body: data)
    }

    @discardableResult
    static func save(kind: String, id: String, body: Data) -> URL? {
        let url = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))__\(kind)__\(id).json")
        guard (try? body.write(to: url, options: .atomic)) != nil else { return nil }
        let all = files(sent: true) + files(sent: false)
        let sorted = all.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if sorted.count > keep { for f in sorted.prefix(sorted.count - keep) { remove(f) } }
        return url
    }

    /// Not yet on the Mac, oldest first.
    static func pending() -> [(url: URL, kind: String, id: String)] {
        files(sent: false).compactMap { url in
            let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: "__")
            guard parts.count == 3 else { return nil }
            return (url, parts[1], parts[2])
        }
    }

    /// The Mac has it: kept (for Copy Report) but not sent again.
    static func markSent(_ url: URL) {
        let to = sentDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.moveItem(at: url, to: to)
    }

    static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    private static var sentDir: URL {
        let d = dir.appendingPathComponent("sent", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func files(sent: Bool) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: sent ? sentDir : dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Copy Report

    /// Reports from after `since`, newest first, as one text to paste.
    static func report(since: Double = 0, limit: Int = 300_000) -> String {
        let all = (files(sent: true) + files(sent: false))
            .filter { (Double($0.lastPathComponent.components(separatedBy: "__").first ?? "") ?? 0) / 1000 > since }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        var out = "Superagent \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") "
            + "(\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")), "
            + "\(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        out += "\n--- now ---\n\(HangGuard.shared.live())\n"
        for f in all {
            guard let body = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let piece = "\n--- \(f.lastPathComponent.components(separatedBy: "__").dropFirst().first ?? "") ---\n\(body)\n"
            if out.utf8.count + piece.utf8.count > limit { out += "\n(older reports left out)\n"; break }
            out += piece
        }
        return out
    }

    /// What went wrong since the app last asked, worth asking about: a crash, a
    /// kill, Apple's report, or a freeze of two seconds or more. Nil when nothing.
    static func worthAsking(since: Double) -> String? {
        var worst: String?
        for f in files(sent: true) + files(sent: false) {
            let parts = f.deletingPathExtension().lastPathComponent.components(separatedBy: "__")
            guard parts.count == 3, (Double(parts[0]) ?? 0) / 1000 > since else { continue }
            switch parts[1] {
            case "exit", "metrickit": return "Superagent stopped unexpectedly last time."
            case "hang":
                if let d = try? Data(contentsOf: f),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let s = o["seconds"] as? Double, s >= 2 || o["ongoing"] as? Bool == true {
                    worst = "Superagent stopped responding for \(String(format: "%.1f", s)) seconds."
                }
            default: break
            }
        }
        return worst
    }

    /// TestFlight (and debug) builds ask after a crash; the App Store build does not.
    static var asksAfterCrash: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

// MARK: - Where the main thread is

/// Where the main thread is while it is stuck. A freeze report said how big the chat was
/// and never what the app was doing: six reports in, the cause was still a guess. This
/// reads the main thread's registers and walks its frame-pointer chain from another
/// thread, then names each address (image and nearest symbol), so the next report shows
/// the real stack. Reading only: it never changes what the main thread does.
enum StackSampler {
    /// The main thread's Mach port, taken on the main thread at launch.
    nonisolated(unsafe) static var mainPort: mach_port_t = 0

    @MainActor static func start() { mainPort = mach_thread_self() }

    /// Up to `max` return addresses of the main thread, innermost first; empty if it could not be read.
    static func addresses(max: Int = 48) -> [UInt] {
        #if arch(arm64)
        let port = mainPort
        guard port != 0 else { return [] }
        // Nothing may allocate or lock while the thread is stopped (it might hold the lock):
        // everything lands in a buffer made beforehand, and symbols are looked up after.
        let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: max)
        defer { buffer.deallocate() }
        var count = 0
        guard thread_suspend(port) == KERN_SUCCESS else { return [] }
        var state = arm_thread_state64_t()
        var size = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(size)) {
                thread_get_state(port, ARM_THREAD_STATE64, $0, &size)
            }
        }
        if kr == KERN_SUCCESS {
            let strip: (UInt64) -> UInt = { UInt($0 & 0x0000_007F_FFFF_FFFF) }
            buffer[count] = strip(state.__pc); count += 1
            if count < max { buffer[count] = strip(state.__lr); count += 1 }
            var fp = UInt(state.__fp)
            var pair: (UInt, UInt) = (0, 0)
            while count < max, fp != 0, fp % 8 == 0 {
                var got: vm_size_t = 0
                let ok = withUnsafeMutablePointer(to: &pair) {
                    vm_read_overwrite(mach_task_self_, vm_address_t(fp), 16, vm_address_t(UInt(bitPattern: $0)), &got)
                }
                guard ok == KERN_SUCCESS, got == 16 else { break }
                let ret = strip(UInt64(pair.1))
                if ret == 0 { break }
                buffer[count] = ret; count += 1
                if pair.0 <= fp { break }
                fp = pair.0
            }
        }
        thread_resume(port)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
        #else
        return []
        #endif
    }

    /// "Image+offset symbol" for each address.
    static func describe(_ addrs: [UInt]) -> [String] {
        addrs.map { a in
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: a), &info) != 0 else { return String(a, radix: 16) }
            let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
            let base = UInt(bitPattern: info.dli_fbase)
            let sym = info.dli_sname.map { String(cString: $0) } ?? "?"
            return "\(image)+\(a &- base) \(sym)"
        }
    }

    /// One sample, ready for the report.
    static func sample() -> [String] { describe(addresses()) }
}
