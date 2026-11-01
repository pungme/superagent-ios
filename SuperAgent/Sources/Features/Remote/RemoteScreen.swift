import SwiftUI
import UIKit

// MARK: - The surface

/// The picture of the Mac's screen, fitted to the view, and everything that
/// sits on it: the pointer, a mark where a tap landed, and the gestures.
/// UIKit on purpose: frames and pointer moves set layer properties directly.
@MainActor
final class RemoteSurfaceView: UIView {
    private let picture = CALayer()
    private let pointer = CAShapeLayer()
    private let ripple = CAShapeLayer()
    private let gestures = PageGestureView()
    private(set) var pictureSize: CGSize = .zero
    /// The Mac's own pointer, as the last frame said.
    private(set) var macCursor: CGPoint?
    /// Where the pointer is drawn from (the phone's own in trackpad mode).
    var shownCursor: CGPoint? { didSet { placePointer() } }
    var handle: ((PageGestureEvent) -> Void)? { didSet { gestures.handle = handle } }
    var trackpad = false { didSet { gestures.trackpad = trackpad } }
    var onResize: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 1)
        clipsToBounds = true
        picture.magnificationFilter = .linear
        picture.minificationFilter = .trilinear
        picture.contentsGravity = .resize
        picture.backgroundColor = UIColor(white: 0.12, alpha: 1).cgColor
        layer.addSublayer(picture)
        pointer.path = Self.arrow(CGSize(width: 14, height: 21))
        pointer.fillColor = UIColor.black.cgColor
        pointer.strokeColor = UIColor.white.cgColor
        pointer.lineWidth = 1.4
        pointer.lineJoin = .round
        pointer.bounds = CGRect(x: 0, y: 0, width: 14, height: 21)
        pointer.anchorPoint = .zero
        pointer.shadowOpacity = 0.35
        pointer.shadowRadius = 1.5
        pointer.shadowOffset = CGSize(width: 0, height: 1)
        pointer.isHidden = true
        layer.addSublayer(pointer)
        ripple.fillColor = UIColor.clear.cgColor
        ripple.strokeColor = UIColor.tintColor.cgColor
        ripple.lineWidth = 2
        ripple.opacity = 0
        layer.addSublayer(ripple)
        gestures.frame = bounds
        gestures.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(gestures)
        isAccessibilityElement = false
        gestures.isAccessibilityElement = true
        gestures.accessibilityLabel = "The Mac's screen"
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func arrow(_ size: CGSize) -> CGPath {
        let sx = size.width / 14, sy = size.height / 21
        let p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        p.move(to: pt(0, 0)); p.addLine(to: pt(0, 17)); p.addLine(to: pt(4.2, 13.2)); p.addLine(to: pt(7, 20))
        p.addLine(to: pt(9.8, 18.8)); p.addLine(to: pt(7.1, 12.3)); p.addLine(to: pt(12.8, 12.3)); p.closeSubpath()
        return p
    }

    /// The picture's place in the view: all of it, centred, never cropped.
    static func fitted(_ picture: CGSize, in box: CGSize) -> CGRect {
        guard picture.width > 0, picture.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let s = min(box.width / picture.width, box.height / picture.height)
        let w = picture.width * s, h = picture.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    var drawn: CGRect { Self.fitted(pictureSize, in: bounds.size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        picture.frame = drawn
        CATransaction.commit()
        placePointer()
        onResize?()
    }

    /// A finished frame, from the pipeline (already on the main thread).
    func apply(_ u: RemoteScreenPipeline.Update) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let image = u.image { picture.contents = image }
        if u.size != pictureSize, u.size.width > 0 {
            pictureSize = u.size
            picture.frame = drawn
        }
        CATransaction.commit()
        macCursor = u.cursor
        onFrame?()
    }

    var onFrame: (() -> Void)?

    /// Clear the picture (the stream paused, or it ended).
    func blank() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        picture.contents = nil
        CATransaction.commit()
        pointer.isHidden = true
    }

    /// A point on the picture, 0...1, under a point of the view; nil off the picture.
    func fraction(at p: CGPoint) -> CGPoint? {
        let r = drawn
        guard r.width > 0, r.height > 0 else { return nil }
        let f = CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height)
        guard (0...1).contains(f.x), (0...1).contains(f.y) else { return nil }
        return f
    }

    private func placePointer() {
        guard let c = shownCursor, pictureSize.width > 0 else { pointer.isHidden = true; return }
        let r = drawn
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pointer.position = CGPoint(x: r.minX + c.x * r.width, y: r.minY + c.y * r.height)
        pointer.isHidden = false
        CATransaction.commit()
    }

    func pressed(_ on: Bool) {
        pointer.setAffineTransform(on ? CGAffineTransform(scaleX: 0.85, y: 0.85) : .identity)
    }

    /// A tap's mark, briefly, where it landed: so you see it was taken.
    func markTap(at p: CGPoint) {
        ripple.path = CGPath(ellipseIn: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26), transform: nil)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0]
        fade.duration = 0.35
        ripple.add(fade, forKey: "tap")
    }
}

/// The surface in SwiftUI. Everything that moves is inside it.
struct RemoteSurface: UIViewRepresentable {
    let controller: RemoteController
    var trackpad: Bool

    func makeUIView(context: Context) -> RemoteSurfaceView {
        let v = RemoteSurfaceView()
        controller.attach(surface: v)
        return v
    }

    func updateUIView(_ v: RemoteSurfaceView, context: Context) {
        if v.trackpad != trackpad { v.trackpad = trackpad; controller.modeChanged(trackpad: trackpad) }
    }

    static func dismantleUIView(_ v: RemoteSurfaceView, coordinator: ()) {
        v.handle = nil
    }
}

/// A finger pad: one finger moves the pointer, two scroll, a tap clicks, two
/// fingers tap right-clicks, tap-and-hold drags. The same recognisers as the
/// page mirror's trackpad (PageGestureView).
struct RemoteTrackpad: UIViewRepresentable {
    let controller: RemoteController

    func makeUIView(context: Context) -> PageGestureView {
        let v = PageGestureView()
        v.trackpad = true
        v.handle = { [weak controller] e in controller?.pad(e) }
        v.isAccessibilityElement = true
        v.accessibilityLabel = "Trackpad"
        v.accessibilityHint = "Move one finger to move the pointer. Tap to click. Two fingers scroll."
        return v
    }

    func updateUIView(_ v: PageGestureView, context: Context) {}
}
