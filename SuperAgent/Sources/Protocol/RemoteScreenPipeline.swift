import Foundation
import CoreGraphics
import ImageIO

/// The Mac's screen, decoded and drawn OFF the main thread.
///
/// A frame is a JPEG of the part of the picture that changed (or all of it).
/// Parsing the JSON, decoding the base64 and the JPEG, and drawing the piece
/// into the picture all happen on one background queue; the main thread is
/// handed a finished CGImage and sets it as the contents of ONE layer. Nothing
/// here goes through @State or an observed property: the iOS app has been
/// hung by a view rebuilding on every layout pass, and a screen at ten frames a
/// second must never be able to do that.
final class RemoteScreenPipeline: @unchecked Sendable {
    struct Update: @unchecked Sendable {
        var image: CGImage?
        /// The picture's size in pixels.
        var size: CGSize
        /// The Mac's pointer on the picture, 0...1; nil when it is on another display.
        var cursor: CGPoint?
    }

    private let queue = DispatchQueue(label: "dev.superagent.remote.screen", qos: .userInteractive)
    private let lock = NSLock()
    private var active = false
    private var handler: (@Sendable (Update) -> Void)?
    private var needKey: (@Sendable () -> Void)?
    private var pending: Update?
    private var scheduled = false

    // Touched only on `queue`.
    private var ctx: CGContext?
    private var width = 0
    private var height = 0
    private var last: CGImage?
    private var askedForKey = false

    /// Frames are decoded only while a remote view is on screen.
    func start(handler: @escaping @Sendable (Update) -> Void, needKey: @escaping @Sendable () -> Void) {
        lock.lock(); self.handler = handler; self.needKey = needKey; active = true; lock.unlock()
    }

    func stop() {
        lock.lock(); active = false; handler = nil; needKey = nil; pending = nil; lock.unlock()
        queue.async { [self] in ctx = nil; last = nil; width = 0; height = 0; askedForKey = false }
    }

    /// The next frame must be a whole picture (after a pause, say).
    func forgetPicture() {
        queue.async { [self] in ctx = nil; last = nil; width = 0; height = 0 }
    }

    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }

    /// A decrypted `screen` frame, as the JSON text it arrived as.
    func ingest(_ plain: String) {
        guard isActive else { return }
        queue.async { [self] in
            guard let data = plain.data(using: .utf8),
                  let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
            apply(env.frame)
        }
    }

    /// Tests, and anything else that already has the frame.
    func ingest(_ frame: WireScreenFrame) {
        guard isActive else { return }
        queue.async { [self] in apply(frame) }
    }

    private struct Envelope: Decodable { var frame: WireScreenFrame }

    /// Nothing is drawn after a frame that does not fit the picture: ask again for a whole one.
    private func apply(_ f: WireScreenFrame) {
        let cursor = f.cursor.map { CGPoint(x: $0.x, y: $0.y) }
        if f.jpeg.isEmpty {
            // Only the pointer moved.
            publish(Update(image: last, size: CGSize(width: width, height: height), cursor: cursor))
            return
        }
        guard f.w > 0, f.h > 0, f.w <= 8192, f.h <= 8192, f.rw > 0, f.rh > 0,
              f.x >= 0, f.y >= 0, f.x + f.rw <= f.w, f.y + f.rh <= f.h else { return }
        if f.key || ctx == nil || width != f.w || height != f.h {
            guard f.key else { return askForKey() }
            let space = CGColorSpaceCreateDeviceRGB()
            ctx = CGContext(data: nil, width: f.w, height: f.h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            ctx?.interpolationQuality = .none
            width = f.w; height = f.h
        }
        guard let ctx,
              let jpeg = Data(base64Encoded: f.jpeg),
              let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let piece = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return }
        askedForKey = false
        // CoreGraphics counts from the bottom; the frame from the top.
        ctx.draw(piece, in: CGRect(x: f.x, y: f.h - f.y - f.rh, width: f.rw, height: f.rh))
        last = ctx.makeImage()
        publish(Update(image: last, size: CGSize(width: f.w, height: f.h), cursor: cursor))
    }

    private func askForKey() {
        guard !askedForKey else { return }
        askedForKey = true
        lock.lock(); let ask = needKey; lock.unlock()
        ask?()
    }

    /// The latest wins: a frame still waiting for the main thread is replaced, not queued behind.
    private func publish(_ u: Update) {
        lock.lock()
        guard active else { lock.unlock(); return }
        pending = u
        let go = !scheduled
        scheduled = true
        lock.unlock()
        guard go else { return }
        DispatchQueue.main.async { [self] in
            lock.lock()
            let u = pending; pending = nil; scheduled = false
            let h = handler
            lock.unlock()
            if let u { h?(u) }
        }
    }
}
