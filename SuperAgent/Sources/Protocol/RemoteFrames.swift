import Foundation
import CoreGraphics

// Remote control: the phone as the Mac's screen, trackpad and keyboard.
// Mirrors `Remote control (2.2)` in the desktop's shared/companion-protocol.ts.
//
// Every session is allowed AT THE MAC: the phone asks (after Face ID), a native
// dialog on the Mac asks someone there, a second dialog shows a six-digit code,
// and the phone types it. Nothing on the phone can allow it.

/// Where Remote control stands, as the Mac says it (the `remote` frame).
struct WireRemote: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable { case idle, asking, code, active }
    struct Display: Codable, Hashable, Sendable {
        var name: String
        var width: Double
        var height: Double
    }
    /// Switched on at the Mac. False: nothing below applies and the entry is hidden.
    var available: Bool
    var state: State
    var display: Display?
    /// 'secret' | 'lock' | 'unknown' while the stream is paused.
    var paused: String?
    /// The named app the Mac paused for ("1Password").
    var pausedBy: String?
    var triesLeft: Int?
    /// Why the last session ended or the last request was turned down.
    var ended: String?
    var note: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
        // A state this phone does not know is idle: never "active" by accident.
        state = (try? c.decode(State.self, forKey: .state)) ?? .idle
        display = try c.decodeIfPresent(Display.self, forKey: .display)
        paused = try c.decodeIfPresent(String.self, forKey: .paused)
        pausedBy = try c.decodeIfPresent(String.self, forKey: .pausedBy)
        triesLeft = try c.decodeIfPresent(Int.self, forKey: .triesLeft)
        ended = try c.decodeIfPresent(String.self, forKey: .ended)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    init(available: Bool, state: State, display: Display? = nil, paused: String? = nil, pausedBy: String? = nil,
         triesLeft: Int? = nil, ended: String? = nil, note: String? = nil) {
        self.available = available; self.state = state; self.display = display; self.paused = paused
        self.pausedBy = pausedBy; self.triesLeft = triesLeft; self.ended = ended; self.note = note
    }
}

/// One piece of the Mac's screen (the `screen` frame). `jpeg` covers x,y,rw,rh of
/// a picture that is w×h pixels. A key frame is the whole picture. No `jpeg`
/// only moves the cursor.
struct WireScreenFrame: Codable, Hashable, Sendable {
    struct Cursor: Codable, Hashable, Sendable { var x: Double; var y: Double }
    var seq: Int
    var w: Int
    var h: Int
    var x: Int
    var y: Int
    var rw: Int
    var rh: Int
    var key: Bool
    var jpeg: String
    var cursor: Cursor?
}

/// What the phone sends the Mac (`remote.input`). Points are fractions of the
/// picture of the shared display. Held inside it, as the Mac requires, and the
/// Mac checks all of it again.
enum RemoteAction: Equatable, Sendable {
    case move(CGPoint)
    case click(CGPoint, right: Bool = false, count: Int = 1)
    case down(CGPoint)
    case up(CGPoint)
    case scroll(at: CGPoint, delta: CGSize)
    case text(String)
    /// A key of the Mac's list (letters, digits, named keys), with modifiers.
    case key(String, mods: [RemoteMod] = [])

    enum Mod: String, Sendable { case cmd, shift, opt, ctrl, fn }

    private static func unit(_ v: CGFloat) -> JSONValue { .number(Double(min(1, max(0, v.isFinite ? v : 0)))) }
    private static func sym(_ v: CGFloat) -> JSONValue { .number(Double(min(1, max(-1, v.isFinite ? v : 0)))) }

    var json: JSONValue {
        func at(_ type: String, _ p: CGPoint) -> [String: JSONValue] {
            ["type": .string(type), "x": Self.unit(p.x), "y": Self.unit(p.y)]
        }
        switch self {
        case .move(let p): return .object(at("move", p))
        case .click(let p, let right, let count):
            var o = at("click", p)
            if right { o["button"] = .string("right") }
            if count > 1 { o["count"] = .number(Double(min(3, count))) }
            return .object(o)
        case .down(let p): return .object(at("down", p))
        case .up(let p): return .object(at("up", p))
        case .scroll(let p, let d):
            var o = at("scroll", p)
            o["dx"] = Self.sym(d.width)
            o["dy"] = Self.sym(d.height)
            return .object(o)
        case .text(let t): return .object(["type": .string("text"), "text": .string(t)])
        case .key(let k, let mods):
            var o: [String: JSONValue] = ["type": .string("key"), "key": .string(k)]
            if !mods.isEmpty { o["mods"] = .array(mods.map { .string($0.rawValue) }) }
            return .object(o)
        }
    }
}

typealias RemoteMod = RemoteAction.Mod

/// What the Mac's reasons mean, in words.
enum RemoteWords {
    /// Why a session ended, or a request was turned down.
    static func ended(_ reason: String?) -> String? {
        switch reason {
        case nil, "": return nil
        case "denied": return "The Mac was not allowed. Nothing was started."
        case "expired": return "Nobody allowed it at the Mac in time."
        case "wrong-code": return "That was not the code on the Mac."
        case "cancelled": return "It was cancelled at the Mac."
        case "stopped-at-mac": return "It was stopped at the Mac."
        case "stopped-on-phone": return "Session ended."
        case "hotkey": return "It was stopped at the Mac with ⌥Esc."
        case "phone-left", "phone-silent": return "The connection to the Mac was lost, so the session ended."
        case "idle": return "It ended after ten minutes with nothing done. Start again, and allow it at the Mac."
        case "too-long": return "It ended after two hours. Start again, and allow it at the Mac."
        case "slept": return "The Mac went to sleep, so the session ended."
        case "locked": return "The Mac was locked, so the session ended."
        case "turned-off": return "Remote control was turned off at the Mac."
        case "display-gone": return "The shared display went away."
        case "banner-lost": return "The Mac could not keep its red bar up, so it stopped."
        case "permissions": return "The Mac cannot show its screen yet. Check Screen Recording in its System Settings, then open Superagent again."
        case "no-stop-key": return "The Mac could not hold ⌥Esc, which has to work for this."
        default: return "The session ended."
        }
    }

    /// The stream is paused, said for the person holding the phone.
    static func paused(_ kind: String?, by: String?) -> String {
        if kind == "lock" { return "The Mac is at its lock screen." }
        if let by, !by.isEmpty { return "\(by) is in front on the Mac. Do that part at the Mac." }
        if kind == "secret" { return "A password manager is in front on the Mac. Do that part at the Mac." }
        return "The Mac cannot say what is on its screen right now."
    }
}
