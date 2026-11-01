import SwiftUI
import UIKit

/// How a foldable is held. There is no SwiftUI environment value for it: iOS 27.1
/// adds `UIHingeInteraction`, which reports the hinge's status (closed, partly
/// open, open as far as it goes) and angle to any view it is added to. That is
/// the signal; the simulator's `sim_fold` moves the same hinge ('half' is 90°).
enum DevicePosture: Equatable, Sendable {
    /// One screen in use, as any phone: unfolded, or a phone that does not fold.
    case flat
    /// Closed: the outer screen.
    case folded
    /// Half open, like a laptop: the top screen shows, the bottom screen types.
    case laptop

    /// The posture of a hinge. A laptop is partly open between 60° and 135°: shallower is
    /// nearly shut, wider is nearly flat, and neither has a screen to type on.
    static func classify(closed: Bool, partlyOpen: Bool, angle: Double) -> DevicePosture {
        if closed { return .folded }
        guard partlyOpen else { return .flat }
        let a = (angle * 180 / .pi).rounded()
        return (60...135).contains(a) ? .laptop : .flat
    }
}

/// The posture, kept as a small value that changes only when the hinge crosses
/// from one posture to another: never every degree of angle.
@MainActor
@Observable
final class PostureWatch {
    private(set) var posture: DevicePosture = .flat
    /// Whether this device has a hinge at all.
    private(set) var foldable = false

    func update(_ p: DevicePosture) {
        foldable = true
        if p != posture { posture = p }
    }

    /// Tests, and the debug harness.
    func force(_ p: DevicePosture) { foldable = true; posture = p }
}

/// An invisible view that carries the hinge interaction. Put it in the hierarchy
/// once; it reports into a `PostureWatch`.
struct PostureReader: UIViewRepresentable {
    let watch: PostureWatch

    func makeUIView(context: Context) -> UIView {
        #if DEBUG
        let v = GeometryProbe()
        #else
        let v = UIView()
        #endif
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        if #available(iOS 27.1, *) {
            let w = watch
            v.addInteraction(UIHingeInteraction { _, update in
                // A nil hinge: the view has left a hierarchy that has one.
                guard let hinge = update.hinge else { return }
                let p = DevicePosture.classify(closed: hinge.status == .closed,
                                               partlyOpen: hinge.status == .partiallyOpen,
                                               angle: Double(hinge.angle))
                MainActor.assumeIsolated {
                    w.update(p)
                    #if DEBUG
                    (v as? GeometryProbe)?.record("hinge status=\(hinge.status.rawValue) angle=\(Int(Double(hinge.angle) * 180 / .pi))")
                    #endif
                }
            })
        }
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {}
}

#if DEBUG
/// Debug only: writes the window's and screen's geometry to /tmp when it changes
/// (the simulator shares the Mac's /tmp), to see what a Duo's postures look like to an app.
final class GeometryProbe: UIView {
    private var last = ""
    override func layoutSubviews() {
        super.layoutSubviews()
        record("layout")
    }
    func record(_ why: String) {
        guard let w = window else { return }
        let scr = w.screen
        let line = "\(why) window=\(w.bounds.size) safe=\(w.safeAreaInsets) screen=\(scr.bounds.size) native=\(scr.nativeBounds.size) scale=\(scr.scale) screens=\(UIScreen.screens.map { "\($0.bounds.size)/\($0.nativeBounds.size)/\($0 == w.screen ? "mine" : "other")" }) scenes=\(UIApplication.shared.connectedScenes.map { "\(type(of: $0))/\($0.session.role.rawValue)" }) orient=\(w.windowScene?.effectiveGeometry.interfaceOrientation.rawValue ?? -1) hsize=\(traitCollection.horizontalSizeClass.rawValue) vsize=\(traitCollection.verticalSizeClass.rawValue)"
        guard line != last else { return }
        last = line
        if let h = FileHandle(forWritingAtPath: "/tmp/rc-geometry.log") ?? { FileManager.default.createFile(atPath: "/tmp/rc-geometry.log", contents: nil); return FileHandle(forWritingAtPath: "/tmp/rc-geometry.log") }() {
            h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
        }
    }
}
#endif
