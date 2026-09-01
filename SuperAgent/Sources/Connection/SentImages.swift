import Foundation
import UIKit

/// Thumbnails of the pictures you sent, kept on this phone.
///
/// The transcript event for a message carries only how many images there were
/// and how big they are — the bytes go to the agent, not into the log, which is
/// right: a conversation replayed on three devices should not drag its
/// attachments across the relay three times. But it left the phone showing
/// "1 image" as a line of grey text under a message whose picture it had in its
/// hands a second earlier.
///
/// So it keeps a thumbnail. Small (a 600pt long edge, JPEG), in Caches so the
/// system can reclaim it, keyed by the message's local id — which is the id the
/// event comes back with, so the bubble can find it again after the round trip.
enum SentImages {
    private static let longEdge: CGFloat = 600

    /// What was sent, held until it is safely on disk.
    ///
    /// Shrinking and writing happen off the main actor, which is right — but the
    /// bubble for a message renders in the same frame the message is queued, and
    /// its `.task(id:)` runs once. It was reading the directory before the file
    /// existed, finding nothing, falling through to asking the Mac for a
    /// thumbnail the Mac did not have yet either, and settling on "1 image" as
    /// grey text — for a picture the app had in its hands a moment earlier, and
    /// which never came back because nothing re-runs that task.
    ///
    /// So the bytes are remembered synchronously here, and dropped once the disk
    /// copy exists. Nothing is held for longer than that write takes.
    private static let pending = Pending()

    private final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: [Data]] = [:]

        func put(_ key: String, _ images: [Data]) {
            lock.lock(); defer { lock.unlock() }
            items[key] = images
        }

        func get(_ key: String) -> [Data]? {
            lock.lock(); defer { lock.unlock() }
            return items[key]
        }

        func drop(_ key: String) {
            lock.lock(); defer { lock.unlock() }
            items[key] = nil
        }
    }

    private static var root: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("sent-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ messageId: String, _ index: Int) -> URL? {
        // The id is ours (L-<uuid prefix>), but a path is a path: never let one
        // walk out of the directory it belongs in.
        let safe = messageId.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return root?.appendingPathComponent("\(safe)-\(index).jpg")
    }

    /// Remember what a message was sent with. Off the main actor: this is disk
    /// work on the way out, and nothing is waiting for it.
    static func keep(messageId: String, images: [Data]) {
        guard !images.isEmpty else { return }
        // Synchronous, so a bubble rendering in this same frame can find it.
        pending.put(messageId, images)
        let ids = images.enumerated().map { ($0.offset, $0.element) }
        Task.detached(priority: .utility) {
            for (i, data) in ids {
                guard let url = url(messageId, i), let thumb = shrink(data) else { continue }
                try? thumb.write(to: url, options: .atomic)
            }
            // On disk now; the copy in memory has nothing left to cover.
            pending.drop(messageId)
        }
    }

    /// The thumbnails for a message, in the order they were sent.
    static func load(messageId: String, count: Int) -> [UIImage] {
        // Memory first: for a message just sent, this is the only place it is.
        if let held = pending.get(messageId) {
            let images = held.prefix(count).compactMap(UIImage.init(data:))
            if !images.isEmpty { return images }
        }
        return (0..<count).compactMap { i in
            guard let url = url(messageId, i), let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    /// A picture worth keeping, not the one that was sent: the original went to
    /// the agent at full size and has no business filling the cache twice.
    private static func shrink(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, longEdge / max(w, h))
        if scale >= 1 { return image.jpegData(compressionQuality: 0.7) }
        let size = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.7)
    }
}
