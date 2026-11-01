import Foundation
import CoreGraphics
import UIKit
import Testing
@testable import SuperAgent

/// Control this Mac, the phone's half: the frames it reads, the actions it sends,
/// the keys, the posture, and the screen drawn from pieces. Nothing here touches a Mac.
@MainActor
struct RemoteControlTests {
    private func fixture() throws -> ProtocolTests.Frames {
        let url = try #require(Bundle(for: Marker.self).url(forResource: "frames", withExtension: "json"))
        return try JSONDecoder().decode(ProtocolTests.Frames.self, from: Data(contentsOf: url))
    }
    private final class Marker {}
    private final class Box<T>: @unchecked Sendable { var v: T; init(_ v: T) { self.v = v } }

    // MARK: protocol

    @Test func readsTheRemoteAndScreenFrames() throws {
        let f = try fixture()
        guard case let .remote(off) = f.server[10] else { Issue.record("remote off"); return }
        #expect(off.available == false && off.state == .idle)
        guard case let .remote(asking) = f.server[11] else { Issue.record("asking"); return }
        #expect(asking.state == .asking)
        guard case let .remote(code) = f.server[12] else { Issue.record("code"); return }
        #expect(code.state == .code && code.triesLeft == 2)
        guard case let .remote(active) = f.server[13] else { Issue.record("active"); return }
        #expect(active.state == .active && active.paused == "secret" && active.pausedBy == "1Password")
        #expect(active.display?.name == "Main display" && active.display?.width == 1512)
        guard case let .remote(ended) = f.server[14] else { Issue.record("ended"); return }
        #expect(ended.ended == "idle" && ended.note?.contains("Screen Recording") == true)
        guard case let .screen(key) = f.server[15] else { Issue.record("screen"); return }
        #expect(key.key && key.w == 1440 && key.h == 935 && key.cursor?.x == 0.25)
        guard case let .screen(move) = f.server[16] else { Issue.record("cursor only"); return }
        #expect(move.jpeg.isEmpty && move.cursor == nil)
    }

    @Test func aStateItDoesNotKnowIsIdleNeverActive() throws {
        let json = #"{"available":true,"state":"hovering"}"#
        let r = try JSONDecoder().decode(WireRemote.self, from: Data(json.utf8))
        #expect(r.state == .idle)
    }

    @Test func aMacFromBeforeSaysNothingAboutIt() throws {
        let old = try JSONDecoder().decode(WireMachine.self, from: Data(#"{"name":"Mac","appVersion":"2.0","protocol":1}"#.utf8))
        #expect(old.remoteControl == nil)
        let new = try JSONDecoder().decode(WireMachine.self, from: Data(#"{"name":"Mac","appVersion":"2.2","protocol":1,"remoteControl":true}"#.utf8))
        #expect(new.remoteControl == true)
    }

    // MARK: hidden unless the Mac says so

    private func connection() -> Connection {
        let m = PairedMachine(id: "t", name: "Mac", relay: "wss://example.invalid", deviceId: "d",
                              secret: Data(repeating: 1, count: 32), token: "t", pairedAt: .now)
        return Connection(machine: m)
    }

    @Test func theEntryShowsOnlyWhenTheMacAdvertisesItAndIsReachable() {
        let c = connection()
        #expect(c.remoteAvailable == false)
        c._applyForTests(.welcome(machine: WireMachine(name: "Mac", appVersion: "2.2", protocolVersion: 1, remoteControl: true), tree: [], chats: []))
        #expect(c.state == .connected)
        #expect(c.remoteAvailable == true)
        // The Mac switched it off while connected.
        c._applyForTests(.remote(WireRemote(available: false, state: .idle)))
        #expect(c.remoteAvailable == false)
        c._applyForTests(.remote(WireRemote(available: true, state: .idle)))
        #expect(c.remoteAvailable == true)
        // A fresh welcome forgets what was said before it.
        c._applyForTests(.welcome(machine: WireMachine(name: "Mac", appVersion: "2.1", protocolVersion: 1), tree: [], chats: []))
        #expect(c.remoteAvailable == false)
    }

    // MARK: actions

    @Test func actionsAreHeldInsideThePictureAndWhatTheMacTakes() {
        func obj(_ a: RemoteAction) -> [String: JSONValue] {
            guard case .object(let o) = a.json else { return [:] }
            return o
        }
        #expect(obj(.move(CGPoint(x: -3, y: 9)))["x"] == .number(0))
        #expect(obj(.move(CGPoint(x: -3, y: 9)))["y"] == .number(1))
        #expect(obj(.move(CGPoint(x: .nan, y: 0.5)))["x"] == .number(0))
        // A flick is at most the picture; the Mac takes -1...1.
        #expect(obj(.scroll(at: .zero, delta: CGSize(width: 0, height: 7)))["dy"] == .number(1))
        #expect(obj(.click(CGPoint(x: 0.5, y: 0.5), right: true, count: 9))["button"] == .string("right"))
        #expect(obj(.click(CGPoint(x: 0.5, y: 0.5), right: true, count: 9))["count"] == .number(3))
        #expect(obj(.click(CGPoint(x: 0.5, y: 0.5)))["button"] == nil)
        let key = obj(.key("space", mods: [.cmd]))
        #expect(key["key"] == .string("space"))
        #expect(key["mods"] == .array([.string("cmd")]))
        #expect(obj(.text("héllo"))["text"] == .string("héllo"))
    }

    // MARK: keys

    @Test func aTypedCharacterIsAKeyWhenAModifierIsHeld() {
        #expect(RemoteKeys.key(for: "a")?.name == "a" && RemoteKeys.key(for: "a")?.shift == false)
        #expect(RemoteKeys.key(for: "A")?.name == "a" && RemoteKeys.key(for: "A")?.shift == true)
        #expect(RemoteKeys.key(for: " ")?.name == "space")
        #expect(RemoteKeys.key(for: "7")?.name == "7")
        #expect(RemoteKeys.key(for: "[")?.name == "[")
        // Not on the Mac's key list: text, never a guess.
        #expect(RemoteKeys.key(for: "é") == nil)
        #expect(RemoteKeys.key(for: "!") == nil)
        #expect(RemoteKeys.key(for: "👋") == nil)
    }

    @Test func modifiersStayDownForOneKey() {
        let m = RemoteModifiers()
        m.toggle(.cmd); m.toggle(.shift)
        #expect(m.any)
        #expect(m.take() == [.cmd, .shift])
        #expect(!m.any && m.take().isEmpty)
        m.toggle(.opt); m.toggle(.opt)
        #expect(!m.any)
    }

    @Test func theControllerSendsKeysWithTheModifiersAndLetsGo() async throws {
        let c = RemoteController()
        var sent: [RemoteAction] = []
        c.pump.send = { sent.append(contentsOf: $0) }
        c.modifiers.toggle(.cmd)
        c.type("c")
        c.type("hi")
        c.pump.flush()
        try await Task.sleep(for: .milliseconds(80))
        // ⌘C, then the rest as text: the modifier was let go after one key.
        #expect(sent == [.key("c", mods: [.cmd]), .text("hi")])
        #expect(c.modifiers.any == false)
        // A capital with Shift down is Shift+key, once.
        sent = []
        c.type("A")
        c.modifiers.toggle(.shift)
        c.type("b")
        c.pump.flush()
        try await Task.sleep(for: .milliseconds(80))
        #expect(sent == [.text("A"), .key("b", mods: [.shift])])
    }

    @Test func theMacShortcutsAreAllowedKeys() {
        // What the keyboard sends must be keys the Mac takes (shared/remote-control.ts REMOTE_KEYS).
        let allowed: Set<String> = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
            .union(["=", "-", "[", "]", "'", ";", "\\", ",", "/", ".", "`"])
            .union(["return", "tab", "space", "delete", "forwarddelete", "escape", "left", "right", "up", "down",
                    "home", "end", "pageup", "pagedown"])
            .union((1...12).map { "f\($0)" })
        for name in ["escape", "tab", "space", "up", "down", "left", "right", "delete", "return", "z"] { #expect(allowed.contains(name)) }
        for n in 1...12 { #expect(allowed.contains(RemoteKeys.function(n))) }
        for code: UIKeyboardHIDUsage in [.keyboardLeftArrow, .keyboardEscape, .keyboardDeleteForward, .keyboardPageDown,
                                         .keyboardReturnOrEnter, .keyboardDeleteOrBackspace, .keyboardTab] {
            #expect(allowed.contains(RemoteKeys.named(code) ?? "?"))
        }
        #expect(RemoteKeys.named(.keyboardA) == nil)
    }

    // MARK: the input pump

    @Test func movesKeepTheLatestScrollsAddUpAndOrderIsKept() async throws {
        let pump = RemoteInputPump()
        var batches: [[RemoteAction]] = []
        pump.send = { batches.append($0) }
        pump.post(.move(CGPoint(x: 0.1, y: 0.1)))
        pump.post(.move(CGPoint(x: 0.2, y: 0.2)))
        pump.post(.move(CGPoint(x: 0.3, y: 0.3)))
        pump.post(.scroll(at: CGPoint(x: 0.5, y: 0.5), delta: CGSize(width: 0, height: 0.1)))
        pump.post(.scroll(at: CGPoint(x: 0.5, y: 0.5), delta: CGSize(width: 0, height: 0.2)))
        // A click goes at once, after what was waiting.
        pump.post(.click(CGPoint(x: 0.3, y: 0.3)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(batches.count == 1)
        let b = try #require(batches.first)
        #expect(b.count == 3)
        #expect(b[0] == .move(CGPoint(x: 0.3, y: 0.3)))
        guard case let .scroll(_, d) = b[1] else { Issue.record("scroll"); return }
        #expect(abs(d.height - 0.3) < 1e-9)
        #expect(b[2] == .click(CGPoint(x: 0.3, y: 0.3)))
    }

    @Test func aRefusalFromTheMacIsPassedOnInItsWords() async throws {
        let pump = RemoteInputPump()
        var said: [String] = []
        pump.onRefused = { said.append($0) }
        pump.send = { _ in throw RpcError(code: "unavailable", message: "1Password is in the way on the Mac.") }
        pump.post(.key("a"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(said == ["1Password is in the way on the Mac."])
    }

    @Test func nothingIsSentWhilePaused() {
        let c = RemoteController()
        var sent = 0
        c.pump.send = { _ in sent += 1 }
        c.enabled = false
        c.type("a"); c.press("return"); c.shortcut("space", [.cmd])
        c.pad(.tap(.zero, fingers: 1))
        c.pump.flush()
        #expect(sent == 0)
    }

    // MARK: posture

    @Test func aLaptopIsPartlyOpenBetweenSixtyAndAHundredAndThirtyFiveDegrees() {
        func p(_ closed: Bool, _ part: Bool, _ deg: Double) -> DevicePosture {
            DevicePosture.classify(closed: closed, partlyOpen: part, angle: deg * .pi / 180)
        }
        #expect(p(true, false, 0) == .folded)
        #expect(p(false, true, 90) == .laptop)
        #expect(p(false, true, 60) == .laptop)
        #expect(p(false, true, 135) == .laptop)
        #expect(p(false, true, 30) == .flat)
        #expect(p(false, true, 160) == .flat)
        #expect(p(false, false, 180) == .flat)
    }

    @Test func theWatchChangesOnlyWhenThePostureDoes() {
        let w = PostureWatch()
        #expect(w.posture == .flat && !w.foldable)
        w.update(.laptop)
        #expect(w.posture == .laptop && w.foldable)
        w.update(.flat)
        #expect(w.posture == .flat)
    }

    // MARK: the picture

    private func jpeg(_ size: CGSize, _ color: UIColor) -> Data {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { g in
            color.setFill(); g.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 1)!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    @Test func aPieceIsDrawnWhereItBelongsAndNotOffTheMainThread() async throws {
        let pipe = RemoteScreenPipeline()
        let got = Box<[RemoteScreenPipeline.Update]>([])
        let onMain = Box<[Bool]>([])
        pipe.start(handler: { u in got.v.append(u); onMain.v.append(Thread.isMainThread) }, needKey: {})
        // A whole picture (blue), then a red piece in the top left, then a green one at the bottom right.
        func frame(_ data: Data, key: Bool, x: Int, y: Int, w: Int, h: Int) -> WireScreenFrame {
            WireScreenFrame(seq: 1, w: 200, h: 100, x: x, y: y, rw: w, rh: h, key: key,
                            jpeg: data.base64EncodedString(), cursor: .init(x: 0.5, y: 0.25))
        }
        pipe.ingest(frame(jpeg(CGSize(width: 200, height: 100), .blue), key: true, x: 0, y: 0, w: 200, h: 100))
        pipe.ingest(frame(jpeg(CGSize(width: 40, height: 20), .red), key: false, x: 0, y: 0, w: 40, h: 20))
        pipe.ingest(frame(jpeg(CGSize(width: 40, height: 20), .green), key: false, x: 160, y: 80, w: 40, h: 20))
        try await Task.sleep(for: .milliseconds(400))
        let last = try #require(got.v.last)
        // Handed over on the main thread, finished: nothing was decoded there.
        #expect(!onMain.v.isEmpty && onMain.v.allSatisfy { $0 })
        #expect(last.size == CGSize(width: 200, height: 100))
        #expect(last.cursor == CGPoint(x: 0.5, y: 0.25))
        let img = try #require(last.image)
        let tl = pixel(img, 10, 10), br = pixel(img, 190, 90), mid = pixel(img, 100, 50)
        #expect(tl.r > 200 && tl.b < 60)
        #expect(br.g > 100 && br.r < 60 && br.b < 60)
        #expect(mid.b > 200 && mid.r < 60)
        pipe.stop()
    }

    @Test func aPieceBeforeAWholePictureAsksForOne() async throws {
        let pipe = RemoteScreenPipeline()
        let asked = Box(0)
        pipe.start(handler: { _ in }, needKey: { asked.v += 1 })
        let f = WireScreenFrame(seq: 5, w: 200, h: 100, x: 0, y: 0, rw: 40, rh: 20, key: false,
                                jpeg: jpeg(CGSize(width: 40, height: 20), .red).base64EncodedString(), cursor: nil)
        pipe.ingest(f)
        pipe.ingest(f)
        try await Task.sleep(for: .milliseconds(200))
        #expect(asked.v == 1)
        pipe.stop()
    }

    @Test func nonsenseFramesDrawNothing() async throws {
        let pipe = RemoteScreenPipeline()
        let n = Box(0)
        pipe.start(handler: { _ in n.v += 1 }, needKey: {})
        let good = jpeg(CGSize(width: 40, height: 20), .red).base64EncodedString()
        for (w, h, x, y, rw, rh) in [(0, 100, 0, 0, 10, 10), (200, 100, 190, 0, 40, 20), (200, 100, -1, 0, 10, 10),
                                      (99999, 99999, 0, 0, 10, 10), (200, 100, 0, 0, 0, 0)] {
            pipe.ingest(WireScreenFrame(seq: 1, w: w, h: h, x: x, y: y, rw: rw, rh: rh, key: true, jpeg: good, cursor: nil))
        }
        pipe.ingest(WireScreenFrame(seq: 1, w: 200, h: 100, x: 0, y: 0, rw: 40, rh: 20, key: true, jpeg: "not base64!!", cursor: nil))
        try await Task.sleep(for: .milliseconds(200))
        #expect(n.v == 0)
        pipe.stop()
    }

    @Test func framesAreDroppedWhenNoRemoteViewIsUp() async throws {
        let pipe = RemoteScreenPipeline()
        let n = Box(0)
        pipe.ingest(WireScreenFrame(seq: 1, w: 40, h: 20, x: 0, y: 0, rw: 40, rh: 20, key: true,
                                    jpeg: jpeg(CGSize(width: 40, height: 20), .red).base64EncodedString(), cursor: nil))
        pipe.start(handler: { _ in n.v += 1 }, needKey: {})
        try await Task.sleep(for: .milliseconds(150))
        #expect(n.v == 0)
        pipe.stop()
    }

    // MARK: the surface

    @Test func thePictureIsFittedAndNeverCropped() {
        let r = RemoteSurfaceView.fitted(CGSize(width: 1440, height: 900), in: CGSize(width: 400, height: 800))
        #expect(abs(r.width - 400) < 0.01 && abs(r.height - 250) < 0.01)
        #expect(abs(r.minY - 275) < 0.01 && r.minX == 0)
        let wide = RemoteSurfaceView.fitted(CGSize(width: 1440, height: 900), in: CGSize(width: 1000, height: 300))
        #expect(abs(wide.height - 300) < 0.01 && abs(wide.width - 480) < 0.01)
        #expect(RemoteSurfaceView.fitted(.zero, in: CGSize(width: 10, height: 10)) == .zero)
    }

    @Test func aTouchBecomesAPointOnThePictureOrNothing() {
        let v = RemoteSurfaceView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        v.apply(RemoteScreenPipeline.Update(image: nil, size: CGSize(width: 1440, height: 900), cursor: nil))
        v.layoutIfNeeded()
        let f = v.fraction(at: CGPoint(x: 200, y: 400))
        #expect(f != nil && abs(f!.x - 0.5) < 0.001 && abs(f!.y - 0.5) < 0.001)
        // On the black bars above and below the picture: no click lands on the Mac.
        #expect(v.fraction(at: CGPoint(x: 200, y: 10)) == nil)
        #expect(v.fraction(at: CGPoint(x: 200, y: 790)) == nil)
    }

    // MARK: words

    @Test func everyReasonTheMacGivesHasWordsAndNoneBlamesThePhoneForTheMac() {
        for why in ["denied", "expired", "wrong-code", "cancelled", "stopped-at-mac", "stopped-on-phone", "hotkey",
                    "phone-left", "phone-silent", "idle", "too-long", "slept", "locked", "turned-off", "display-gone",
                    "banner-lost", "permissions", "no-stop-key"] {
            #expect(RemoteWords.ended(why)?.isEmpty == false, Comment(rawValue: why))
        }
        #expect(RemoteWords.ended(nil) == nil && RemoteWords.ended("") == nil)
        #expect(RemoteWords.ended("something-new") == "The session ended.")
        #expect(RemoteWords.paused("secret", by: "1Password").contains("1Password"))
        #expect(RemoteWords.paused("lock", by: nil).contains("lock screen"))
    }
}
