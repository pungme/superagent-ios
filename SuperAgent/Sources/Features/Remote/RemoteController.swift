import SwiftUI
import UIKit

/// The keys the Mac takes (its helper's own names), and how a typed character becomes one.
enum RemoteKeys {
    static let marks: Set<Character> = ["=", "-", "[", "]", "'", ";", "\\", ",", "/", ".", "`"]

    /// A typed character as a key, and whether Shift made it: "a" is a, "A" is Shift+a.
    /// Characters that need a layout the Mac key list lacks (accents, emoji, "!") are text.
    static func key(for ch: Character) -> (name: String, shift: Bool)? {
        if ch == " " { return ("space", false) }
        guard ch.unicodeScalars.count == 1, let s = ch.unicodeScalars.first, s.isASCII else { return nil }
        if ch.isLetter { return (String(ch).lowercased(), ch.isUppercase) }
        if ch.isNumber || marks.contains(ch) { return (String(ch), false) }
        return nil
    }

    /// The Mac's names for the keys a hardware keyboard sends that UIKeyInput does not hand on.
    static func named(_ code: UIKeyboardHIDUsage) -> String? {
        switch code {
        case .keyboardLeftArrow: "left"
        case .keyboardRightArrow: "right"
        case .keyboardUpArrow: "up"
        case .keyboardDownArrow: "down"
        case .keyboardEscape: "escape"
        case .keyboardHome: "home"
        case .keyboardEnd: "end"
        case .keyboardPageUp: "pageup"
        case .keyboardPageDown: "pagedown"
        case .keyboardDeleteForward: "forwarddelete"
        case .keyboardTab: "tab"
        case .keyboardReturnOrEnter: "return"
        case .keyboardDeleteOrBackspace: "delete"
        default: nil
        }
    }

    static func function(_ n: Int) -> String { "f\(n)" }
}

/// The modifiers held for the next key: tap one, then a key, and it is that key
/// with the modifier. They let go after one key.
@MainActor
@Observable
final class RemoteModifiers {
    private(set) var held: Set<RemoteMod> = []

    func toggle(_ m: RemoteMod) {
        if held.contains(m) { held.remove(m) } else { held.insert(m) }
    }

    /// The modifiers for the key being pressed now, and let go of.
    func take() -> [RemoteMod] {
        guard !held.isEmpty else { return [] }
        let order: [RemoteMod] = [.ctrl, .opt, .cmd, .shift, .fn]
        let mods = order.filter { held.contains($0) }
        held = []
        return mods
    }

    var any: Bool { !held.isEmpty }
}

/// What the phone sends the Mac, briskly but not wastefully: pointer moves keep
/// only the latest and scrolls add up for one frame (about 30 a second), and
/// anything else (a click, a key) goes at once, after whatever was waiting, so
/// the order is the order things were done in. One request carries what was
/// waiting; the Mac applies it in order and stops at the first refusal.
@MainActor
final class RemoteInputPump {
    var send: (([RemoteAction]) async throws -> Void)?
    /// The Mac said no to something, in its words.
    var onRefused: ((String) -> Void)?
    private(set) var lastSent: Date = .distantPast

    private var queue: [RemoteAction] = []
    private var timer: Task<Void, Never>?

    func post(_ a: RemoteAction) {
        switch a {
        case .move:
            if case .move = queue.last { queue[queue.count - 1] = a } else { queue.append(a) }
            schedule()
        case .scroll(let p, let d):
            if case .scroll(_, let before) = queue.last {
                queue[queue.count - 1] = .scroll(at: p, delta: CGSize(width: max(-1, min(1, before.width + d.width)),
                                                                      height: max(-1, min(1, before.height + d.height))))
            } else { queue.append(a) }
            schedule()
        case .text(let t):
            if case .text(let before) = queue.last { queue[queue.count - 1] = .text(before + t) } else { queue.append(a) }
            schedule()
        default:
            queue.append(a)
            flush()
        }
    }

    func flush() {
        timer?.cancel()
        timer = nil
        guard !queue.isEmpty else { return }
        // At most what one request may hold (32); the rest follows at once.
        let batch = Array(queue.prefix(32))
        queue.removeFirst(batch.count)
        fire(batch)
        if !queue.isEmpty { flush() }
    }

    func reset() {
        timer?.cancel(); timer = nil; queue = []
    }

    private func schedule() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return }
            self?.timer = nil
            self?.flush()
        }
    }

    private func fire(_ batch: [RemoteAction]) {
        lastSent = .now
        guard let send else { return }
        // The request leaves before the first suspension (Connection.rpc), so
        // tasks started in order put their frames on the socket in order.
        Task { [weak self] in
            do { try await send(batch) } catch let e as RpcError where e.code == "unavailable" {
                self?.onRefused?(e.message)
            } catch {}
        }
    }
}

/// Fingers and keys turned into what the Mac should get. Not observable: the
/// pointer moves sixty times a second and goes straight to a layer.
@MainActor
final class RemoteController {
    let pump = RemoteInputPump()
    let modifiers = RemoteModifiers()
    /// The Mac refused something: its words, for a moment on screen.
    var onNotice: ((String) -> Void)?
    /// Nothing is sent while the stream is paused (a password manager is in front on the Mac).
    var enabled = true
    /// A surface that has just come up has no picture: ask the Mac for a whole one.
    var onNeedPicture: (() -> Void)?
    /// The last picture, so a new surface (the layout changed) starts with it.
    private var lastUpdate: RemoteScreenPipeline.Update?

    private weak var surface: RemoteSurfaceView?
    private(set) var trackpad = false
    /// The phone's own pointer (trackpad), 0...1 across the shared display.
    private var cursor = CGPoint(x: 0.5, y: 0.5)
    private var lastLocalMove: Date = .distantPast
    private var holding = false
    private var lastClick: (at: CGPoint, time: Date)?
    private var scrollAt: CGPoint?
    private var glide: Task<Void, Never>?
    private var lastNotice: Date = .distantPast

    init() {
        pump.onRefused = { [weak self] message in
            guard let self else { return }
            // One notice at a time: a finger resting on a password manager is a refusal per move.
            guard Date().timeIntervalSince(lastNotice) > 2 else { return }
            lastNotice = .now
            onNotice?(message)
        }
    }

    /// A finished frame, from the pipeline (on the main thread).
    func deliver(_ u: RemoteScreenPipeline.Update) {
        lastUpdate = u
        surface?.apply(u)
    }

    /// How wide a picture is worth sending: the surface's width in pixels, never more than a Mac frame carries.
    var wantedWidth: Int {
        guard let s = surface, s.bounds.width > 0 else { return 1440 }
        let scale = s.window?.screen.scale ?? 3
        return Int(min(1600, max(480, s.drawn.width * scale)))
    }

    func attach(surface: RemoteSurfaceView) {
        self.surface = surface
        if let u = lastUpdate { surface.apply(u) } else { onNeedPicture?() }
        surface.handle = { [weak self, weak surface] e in
            guard let self, let surface else { return }
            self.surfaceEvent(e, in: surface)
        }
        surface.onFrame = { [weak self] in self?.frameArrived() }
        surface.onResize = { [weak self] in self?.showPointer() }
        showPointer()
    }

    func modeChanged(trackpad on: Bool) {
        trackpad = on
        if holding { pump.post(.up(cursor)); holding = false; surface?.pressed(false) }
        showPointer()
    }

    func stop() {
        glide?.cancel()
        if holding { pump.post(.up(cursor)); holding = false }
        pump.reset()
    }

    // MARK: the pointer

    private func showPointer() {
        guard let surface else { return }
        if trackpad { surface.shownCursor = cursor } else { surface.shownCursor = surface.macCursor }
    }

    /// A frame came with where the Mac's pointer is: the phone's own follows it
    /// once the finger has been still a moment (the Mac's mouse, or a click, moved it).
    private func frameArrived() {
        guard let surface else { return }
        if trackpad {
            if Date().timeIntervalSince(lastLocalMove) > 0.8, !holding, let m = surface.macCursor { cursor = m }
            surface.shownCursor = Date().timeIntervalSince(lastLocalMove) > 0.8 ? surface.macCursor : cursor
        } else {
            surface.shownCursor = surface.macCursor
        }
    }

    // MARK: gestures

    /// A finger on the screen itself: where it is on the picture is where it acts (touch),
    /// or it drives the pointer (trackpad mode).
    private func surfaceEvent(_ e: PageGestureEvent, in surface: RemoteSurfaceView) {
        guard enabled else { return }
        if trackpad { pad(e); return }
        switch e {
        case .tap(let p, let fingers):
            glide?.cancel()
            guard let f = surface.fraction(at: p) else { return }
            click(f, right: fingers > 1)
            surface.markTap(at: p)
        case .pan(let state, let p, let d, let v, _):
            if state == .began { glide?.cancel(); scrollAt = surface.fraction(at: p) ?? CGPoint(x: 0.5, y: 0.5) }
            let at = scrollAt ?? CGPoint(x: 0.5, y: 0.5)
            scroll(d, at: at)
            if state == .ended { fling(v, at: at) }
        case .hold, .pinch:
            break
        }
    }

    /// The trackpad: the pad at the bottom of a Duo, or the screen in trackpad mode.
    func pad(_ e: PageGestureEvent) {
        guard enabled else { return }
        switch e {
        case .tap(_, let fingers):
            glide?.cancel()
            click(cursor, right: fingers > 1)
        case .pan(let state, _, let d, let v, let fingers):
            if state == .began { glide?.cancel() }
            if fingers >= 2 {
                scroll(d, at: cursor)
                if state == .ended { fling(v, at: cursor) }
            } else {
                let span = surface?.drawn.size ?? .zero
                let next = PageMap.moveCursor(cursor, by: d, speed: hypot(v.x, v.y), span: span)
                if next != cursor {
                    cursor = next
                    lastLocalMove = .now
                    surface?.shownCursor = next
                    pump.post(.move(next))
                }
            }
        case .hold(let state):
            if state == .began, !holding {
                holding = true
                pump.post(.down(cursor))
                surface?.pressed(true)
                Haptics.tap()
            } else if state == .ended || state == .cancelled || state == .failed, holding {
                holding = false
                pump.post(.up(cursor))
                surface?.pressed(false)
            }
        case .pinch:
            break
        }
    }

    private func click(_ f: CGPoint, right: Bool) {
        let second = !right && PageMap.isSecondClick(at: f, after: lastClick)
        pump.post(.click(f, right: right, count: second ? 2 : 1))
        lastClick = second || right ? nil : (f, .now)
        Haptics.tap()
    }

    private func scroll(_ d: CGSize, at f: CGPoint) {
        let span = surface?.drawn.size ?? .zero
        guard span.width > 0, span.height > 0 else { return }
        let t = CGSize(width: d.width / span.width, height: d.height / span.height)
        if t != .zero { pump.post(.scroll(at: f, delta: t)) }
    }

    /// Let go mid-swipe: the page carries on and slows, as a flicked page does.
    private func fling(_ v: CGPoint, at f: CGPoint) {
        var step = CGSize(width: v.x / 60, height: v.y / 60)
        guard hypot(step.width, step.height) > 3 else { return }
        glide = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                step = CGSize(width: step.width * 0.9, height: step.height * 0.9)
                if hypot(step.width, step.height) < 0.6 { return }
                self?.scroll(step, at: f)
            }
        }
    }

    // MARK: keys

    /// A typed character: text, or the key it is when a modifier is held.
    func type(_ s: String) {
        guard enabled else { return }
        if modifiers.any, s.count == 1, let ch = s.first, let k = RemoteKeys.key(for: ch) {
            var mods = modifiers.take()
            if k.shift, !mods.contains(.shift) { mods.append(.shift) }
            pump.post(.key(k.name, mods: mods))
            return
        }
        _ = modifiers.take()
        switch s {
        case "\n": pump.post(.key("return"))
        case "\t": pump.post(.key("tab"))
        default: pump.post(.text(s))
        }
    }

    /// A named key (the Mac's name for it), with whatever modifiers are held.
    func press(_ name: String, extra: [RemoteMod] = []) {
        guard enabled else { return }
        var mods = modifiers.take()
        for m in extra where !mods.contains(m) { mods.append(m) }
        pump.post(.key(name, mods: mods))
        Haptics.tap()
    }

    /// A shortcut that is its own button (Spotlight, Mission Control): never also the held modifiers.
    func shortcut(_ name: String, _ mods: [RemoteMod]) {
        guard enabled else { return }
        _ = modifiers.take()
        pump.post(.key(name, mods: mods))
        Haptics.tap()
    }
}
