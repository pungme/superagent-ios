import SwiftUI
import UIKit

/// The Mac's browser pane for one conversation, mirrored: a fresh capture
/// every second or two, a URL bar that opens pages on the Mac, back / forward
/// / reload, and a way to hand what you're looking at to the agent.
///
/// Used two ways, like the desktop's preview: docked above the chat (compact),
/// or filling a sheet.
struct BrowserMirror: View {
    let connection: Connection
    let chat: WireChat
    var compact = false
    var onAttach: ((Data) -> Void)?
    var onHide: (() -> Void)?
    var onExpand: (() -> Void)?
    /// Full screen now: the expand button becomes the way out.
    var expanded = false
    /// Paused while the keyboard is up (the pane is collapsed then) or the app is away.
    var paused = false
    /// Picture in picture: only the page itself, small, for MirrorPiP to frame.
    var pip = false
    /// The page's width over its height, whenever a frame says: the small
    /// picture is cut to the same proportions as the page on the Mac.
    var onAspect: ((CGFloat) -> Void)?

    @State private var shot: WireBrowserShot?
    @State private var image: UIImage?
    /// The frame we already decoded, by its bytes — comparing images themselves
    /// would mean re-encoding two screenshots on every poll.
    @State private var lastFrame: Int?
    @State private var inFlight = false
    /// Asking a pixel narrower than usual, to get bytes out of an older Mac.
    @State private var nudge = false
    @State private var unavailable: String?
    @State private var url = ""
    @State private var opening = false
    @State private var error: String?
    @FocusState private var urlFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if pip { pipFace } else { full }
        }
        // The last frame this conversation showed, so going between the small
        // picture and full screen does not start again from a spinner.
        .onAppear {
            if image == nil { image = MirrorFrames.page[chat.id] }
            report(image)
        }
        .onChange(of: image) { _, new in
            if let new { MirrorFrames.page[chat.id] = new }
            report(new)
        }
        .task(id: [paused, scenePhase != .active].description) {
            // Nothing to mirror while the pane is collapsed or the app is away.
            if !paused, scenePhase == .active { await poll() }
        }
        .alert("Browser", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func report(_ image: UIImage?) {
        guard let image, image.size.height > 0 else { return }
        onAspect?(image.size.width / image.size.height)
    }

    /// The page as a small picture: all of it, in its own proportions, and
    /// nothing else. The card around it is cut to the same shape (see
    /// MirrorPiP.cardSize), so this fits it edge to edge. It used to fill a
    /// fixed card, which cropped a wide page and, worse, let the picture's own
    /// width push the card past the edge of the screen.
    private var pipFace: some View {
        ZStack {
            Theme.panel
            if let image {
                Color.clear.overlay {
                    Image(uiImage: image).resizable().scaledToFit()
                }
                .clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "globe").superFont(18).foregroundStyle(Theme.textTertiary)
                    if unavailable == nil { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private var full: some View {
        VStack(spacing: 0) {
            omnibar
            Group {
                if let image, expanded {
                    // Full screen on a phone, a desktop page is a wide picture
                    // in a tall space: it fits across, and is small. Pinch or
                    // double-tap to go in close, and drag to move around.
                    ZoomableImage(image: image)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else if let image {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .scrollDisabled(compact)
                } else if let unavailable {
                    if compact {
                        Text(unavailable).superFont(12).foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Nothing to show yet", systemImage: "safari",
                                               description: Text(unavailable + "\nType an address above and it opens on the Mac."))
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.content)
            controls
        }
        .background(Theme.panel)
    }

    private var omnibar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").superFont(compact ? 12 : 15).foregroundStyle(Theme.textTertiary)
            TextField("Open a page on the Mac…", text: $url)
                .superFont(compact ? 12.5 : 16)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($urlFocused)
                .onSubmit(open)
            if opening { ProgressView().controlSize(.small) }
            else if !url.isEmpty, url != shot?.url {
                Button(action: open) { Image(systemName: "arrow.right.circle.fill").superFont(compact ? 16 : 20) }
                    .tint(Theme.textPrimary).accessibilityLabel("Open")
            }
            // Close in the top-right, matching the desktop. Reopenable via the
            // Show bar. Was only a chevron in the toolbar below — not recognised.
            if let onHide {
                Button(action: onHide) { Image(systemName: "xmark").superFont(compact ? 12 : 14, weight: .semibold) }
                    .buttonStyle(.plain).tint(Theme.textTertiary).accessibilityLabel("Close the page")
            }
        }
        .padding(.horizontal, compact ? 10 : 12).padding(.vertical, compact ? 6 : 9)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 6 : 8)
    }

    private var controls: some View {
        HStack(spacing: compact ? 18 : 22) {
            Button { nav("back") } label: { Image(systemName: "chevron.left") }.disabled(!(shot?.canGoBack ?? false))
            Button { nav("forward") } label: { Image(systemName: "chevron.right") }.disabled(!(shot?.canGoForward ?? false))
            Button { nav("reload") } label: { Image(systemName: "arrow.clockwise") }
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(expanded ? "Exit full screen" : "Open full screen")
            }
            Spacer()
            if let title = shot?.title, !title.isEmpty, !compact {
                Text(title).superFont(12).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
            }
            if let onAttach {
                Button {
                    if let d = image?.jpegData(compressionQuality: 0.8) { onAttach(d); Haptics.tap() }
                } label: {
                    if compact { Image(systemName: "paperclip") }
                    else { Label("Send to agent", systemImage: "paperclip") }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentFg)
                .controlSize(compact ? .small : .regular)
            }
        }
        .superFont(compact ? 14 : 17, weight: .medium)
        .tint(Theme.textPrimary)
        .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 6 : 10)
        .background(Theme.panel)
    }

    // MARK: Mirroring

    /// While the page is changing, refresh briskly; when it settles, back off —
    /// the capture is a whole JPEG through the relay, not a video stream.
    private func poll() async {
        var quiet = 0
        while !Task.isCancelled {
            let changed = await refresh()
            quiet = changed ? 0 : min(quiet + 1, 4)
            try? await Task.sleep(for: .milliseconds(changed ? 700 : 700 + quiet * 800))
        }
    }

    @discardableResult
    private func refresh() async -> Bool {
        // One capture at a time: a slow round trip must not stack up requests,
        // each carrying a screenshot back.
        if inFlight { return false }
        inFlight = true
        defer { inFlight = false }
        do {
            // What we hold, so a still page costs no bytes; nothing while we
            // have no picture, so one is sent whatever the Mac sent before.
            let s = try await connection.browserShot(chatId: chat.id, sharp: expanded && !pip,
                                                     have: image == nil ? nil : shot?.digest,
                                                     nudge: nudge)
            let previous = shot
            // The Mac tells us when the picture is the one we hold, and sends
            // no bytes with it. Keep what we have: the whole point is that a
            // still page costs nothing.
            if s.unchanged == true {
                shot = WireBrowserShot(url: s.url, title: s.title, canGoBack: s.canGoBack,
                                       canGoForward: s.canGoForward, width: s.width,
                                       height: s.height, jpeg: previous?.jpeg ?? "",
                                       unchanged: true, digest: s.digest ?? previous?.digest)
                unavailable = nil
                // "Unchanged" with nothing to show: a Mac from before digests
                // going by what it last sent to anyone. Ask again, a pixel
                // narrower, and it has new bytes to send (see Connection).
                if image == nil, s.digest == nil { nudge.toggle() }
                return previous?.url != s.url || previous?.title != s.title
            }
            nudge = false
            shot = s
            unavailable = nil
            let frame = s.jpeg.hashValue
            var changed = previous?.url != s.url || previous?.title != s.title
            if frame != lastFrame {
                changed = true
                lastFrame = frame
                // Decoding a JPEG is real work; keep it off the main actor.
                if let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let d = Data(base64Encoded: s.jpeg) else { return nil }
                    return UIImage(data: d)
                }.value {
                    image = img
                }
            }
            if !urlFocused, url.isEmpty || url == previous?.url { url = s.url }
            return changed
        } catch let e as RpcError where e.code == "unavailable" {
            if shot == nil { unavailable = e.message; image = nil }
            return false
        } catch {
            if shot == nil { unavailable = error.localizedDescription }
            return false
        }
    }

    private func open() {
        let target = url.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !opening else { return }
        opening = true
        urlFocused = false
        Task {
            defer { opening = false }
            do {
                url = try await connection.browserOpen(chatId: chat.id, url: target)
                Haptics.tap()
                await refresh()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func nav(_ action: String) {
        Task {
            do { try await connection.browserNav(chatId: chat.id, action: action); try? await Task.sleep(for: .milliseconds(500)); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// The same mirror, filling a sheet.
struct BrowserSheet: View {
    let connection: Connection
    let chat: WireChat
    var onAttach: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BrowserMirror(connection: connection, chat: chat,
                          onAttach: { data in onAttach(data); dismiss() })
                .navigationTitle("Browser")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The Mac's iOS Simulator for one conversation, mirrored the way the browser
/// is: a still every second or so, and taps sent back to the device.
///
/// Lives in this file rather than its own because the Xcode project is checked
/// in and generated by xcodegen, which is not installed here; a new source file
/// would not be compiled.
struct SimulatorMirror: View {
    let connection: Connection
    let chat: WireChat
    var onAttach: ((Data) -> Void)?
    var onHide: (() -> Void)?
    /// Full screen, with the conversation floating over it.
    var onExpand: (() -> Void)?
    /// Full screen now: the expand button becomes the way out.
    var expanded = false
    /// Paused while the keyboard is up or the app is away.
    var paused = false
    /// Picture in picture: only the device's screen, small, for MirrorPiP to frame.
    var pip = false
    /// The screen's width over its height, whenever a frame says.
    var onAspect: ((CGFloat) -> Void)?

    @State private var shot: WireSimulatorShot?
    @State private var image: UIImage?
    @State private var inFlight = false
    @State private var unavailable: String?
    @State private var sending = false
    @Environment(\.scenePhase) private var scenePhase

    private var device: String {
        connection.simulators[chat.id]?.device ?? shot?.device ?? "Simulator"
    }

    var body: some View {
        Group {
            if pip { pipFace } else { full }
        }
        .onAppear {
            if image == nil { image = MirrorFrames.sim[chat.id] }
            if let image, image.size.height > 0 { onAspect?(image.size.width / image.size.height) }
        }
        .onChange(of: image) { _, new in
            guard let new else { return }
            MirrorFrames.sim[chat.id] = new
            if new.size.height > 0 { onAspect?(new.size.width / new.size.height) }
        }
        // Keyed on scenePhase as well as paused, so backgrounding the app
        // cancels the poll — the browser mirror already did this; the simulator
        // one did not, and kept polling (a JPEG a second) while the phone was
        // asleep. That is what quietly drained the relay's daily budget
        // overnight with nobody watching. Only poll while actually on screen.
        .task(id: [paused, scenePhase != .active].description) {
            if !paused, scenePhase == .active { await loop() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh(force: true) } } }
    }

    /// The device's screen as a small picture. Taps go to the frame around it
    /// (full screen), not to the device: at this size a tap is not aimed.
    private var pipFace: some View {
        ZStack {
            Color.black
            if let image {
                Color.clear.overlay { Image(uiImage: image).resizable().scaledToFit() }.clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "iphone").superFont(18).foregroundStyle(.white.opacity(0.5))
                    if unavailable == nil { ProgressView().controlSize(.small).tint(.white) }
                }
            }
        }
    }

    private var full: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "iphone").superFont(12).foregroundStyle(Theme.textTertiary)
                Text(device).superFont(13).lineLimit(1).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if sending { ProgressView().controlSize(.mini) }
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .superFont(13)
                    }
                    .buttonStyle(.plain).tint(Theme.textTertiary)
                    .accessibilityLabel(expanded ? "Exit full screen" : "Open full screen")
                }
                // A close in the top-right, where the desktop puts it, so the
                // pane is obviously dismissable — the chevron in the toolbar
                // below was a hide nobody recognised. Reopenable via the Show bar.
                if let onHide {
                    Button(action: onHide) { Image(systemName: "xmark").superFont(13, weight: .semibold) }
                        .buttonStyle(.plain).tint(Theme.textTertiary).accessibilityLabel("Close the simulator")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.panel)

            screen

            HStack(spacing: 18) {
                Button { Task { await refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).tint(Theme.textSecondary)
                Spacer()
                if let onAttach, let data = image?.jpegData(compressionQuality: 0.8) {
                    Button { onAttach(data) } label: { Image(systemName: "paperclip") }
                        .buttonStyle(.plain).tint(Theme.textSecondary).accessibilityLabel("Send this screen to the agent")
                }
            }
            .superFont(15)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.panel)
        }
    }

    /// Pinched closer: the picture is scaled about the middle of the box and
    /// moved by `pan`; a tap is taken back through both before it is mapped to
    /// the device (see `unzoom`). One finger moves the picture while zoomed,
    /// and is a tap otherwise; the device never gets a swipe from here.
    @State private var zoom: CGFloat = 1
    @State private var zoomLast: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panLast: CGSize = .zero

    /// A point in the box, as it would be with no zoom: where a tap lands on
    /// the picture at rest. Scaling is about the box's centre, then the pan.
    static func unzoom(_ p: CGPoint, in box: CGSize, zoom: CGFloat, pan: CGSize) -> CGPoint {
        let c = CGPoint(x: box.width / 2, y: box.height / 2)
        return CGPoint(x: (p.x - pan.width - c.x) / zoom + c.x,
                       y: (p.y - pan.height - c.y) / zoom + c.y)
    }

    /// The pan held so the picture never leaves the box: at most the overhang.
    static func clampPan(_ pan: CGSize, in box: CGSize, zoom: CGFloat) -> CGSize {
        let mx = max(0, (zoom - 1) * box.width / 2), my = max(0, (zoom - 1) * box.height / 2)
        return CGSize(width: min(mx, max(-mx, pan.width)), height: min(my, max(-my, pan.height)))
    }

    @ViewBuilder
    private var screen: some View {
        GeometryReader { geo in
            ZStack {
                Theme.content
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(zoom)
                        .offset(pan)
                } else if let unavailable {
                    Text(unavailable).superFont(13).foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center).padding()
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            // A tap lands where you put it: the still is the device's own
            // pixels, so the maths is undoing the zoom, then scaledToFit.
            .gesture(
                SpatialTapGesture().onEnded { t in
                    guard let image else { return }
                    let at = Self.unzoom(t.location, in: geo.size, zoom: zoom, pan: pan)
                    guard let px = devicePoint(at, in: geo.size, image: image) else { return }
                    Task { await tap(px) }
                }
            )
            // Two fingers bring it closer, up to five times, and let it go
            // again; one finger moves it about while it is close.
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { v in
                        zoom = min(5, max(1, zoomLast * v))
                        pan = Self.clampPan(pan, in: geo.size, zoom: zoom)
                    }
                    .onEnded { _ in
                        zoomLast = zoom
                        if zoom <= 1 { withAnimation(.spring(response: 0.3)) { pan = .zero; panLast = .zero } }
                        else { panLast = pan }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { g in
                        guard zoom > 1 else { return }
                        pan = Self.clampPan(CGSize(width: panLast.width + g.translation.width,
                                                   height: panLast.height + g.translation.height),
                                            in: geo.size, zoom: zoom)
                    }
                    .onEnded { _ in panLast = pan }
            )
            .animation(.interactiveSpring(), value: zoom)
        }
    }

    /// Where a tap in the view lands on the device, or nil outside the picture.
    private func devicePoint(_ p: CGPoint, in box: CGSize, image: UIImage) -> CGPoint? {
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (box.width - drawn.width) / 2, y: (box.height - drawn.height) / 2)
        let x = (p.x - origin.x) / scale
        let y = (p.y - origin.y) / scale
        guard x >= 0, y >= 0, x <= image.size.width, y <= image.size.height else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func tap(_ p: CGPoint) async {
        sending = true
        defer { sending = false }
        try? await connection.simInput(
            chatId: chat.id,
            action: ["type": .string("tap"), "x": .number(Double(Int(p.x))), "y": .number(Double(Int(p.y)))]
        )
        // Show the result rather than waiting for the next poll.
        try? await Task.sleep(for: .milliseconds(350))
        await refresh(force: true)
    }

    /// Polls while it is on screen, and backs off when the device is not doing
    /// anything: a still screen went from a JPEG a second to nothing at all,
    /// which is most of what a mirror costs.
    private func loop() async {
        var quiet = 0
        while !Task.isCancelled {
            if paused { return }
            let moved = await refresh(force: false)
            quiet = moved ? 0 : min(quiet + 1, 8)
            let wait = quiet == 0 ? 1200 : min(1200 * (quiet + 1), 6000)
            try? await Task.sleep(for: .milliseconds(wait))
        }
    }

    /// Returns whether the picture actually changed, so the loop can slow down.
    @discardableResult
    private func refresh(force: Bool) async -> Bool {
        guard !inFlight, connection.state == .connected else { return false }
        guard force || !paused else { return false }
        inFlight = true
        defer { inFlight = false }
        do {
            // What we hold; nothing while there is no picture, so one is sent.
            let s = try await connection.simShot(chatId: chat.id, have: image == nil ? nil : shot?.digest)
            let previous = shot
            shot = s
            // The Mac says so rather than sending the bytes we hold again.
            if s.unchanged == true {
                shot?.digest = s.digest ?? previous?.digest
                return false
            }
            if let comma = s.url.firstIndex(of: ","),
               let data = Data(base64Encoded: String(s.url[s.url.index(after: comma)...])),
               let ui = UIImage(data: data) {
                image = ui
                unavailable = nil
                return true
            }
            return false
        } catch let e as RpcError {
            unavailable = e.message
            return false
        } catch {
            unavailable = "The simulator isn't available right now."
            return false
        }
    }
}


/// The last picture each conversation's mirror showed. A mirror is drawn by
/// one view when it is small and another when it is full screen; this is what
/// lets the second start from where the first left off.
@MainActor
enum MirrorFrames {
    static var page: [String: UIImage] = [:]
    static var sim: [String: UIImage] = [:]
}

/// A page or the simulator as picture in picture, on a phone: a small card
/// floating over the conversation, the way a video call sits over whatever
/// else you are doing. It docked above the conversation before, which on a
/// phone left half a screen for each and enough of neither.
///
/// Drag it and it settles in the nearest corner. Pinch it bigger or smaller,
/// and it stays that size. Tap it for full screen. The × puts it away (the bar
/// at the top of the conversation brings it back).
struct MirrorPiP<Content: View>: View {
    /// The card's size: wide for a page, tall for a phone's screen.
    let size: CGSize
    let glyph: String
    let label: String
    /// What VoiceOver calls the ×: "Close the page", "Close the simulator".
    let closeLabel: String
    /// The keyboard is up: a card in a bottom corner moves to the top one.
    let keyboardUp: Bool
    let onOpen: () -> Void
    let onClose: () -> Void
    let content: Content

    @AppStorage private var corner: String
    /// How much bigger than its base size the card was pinched to; kept.
    @AppStorage private var scale: Double

    /// `place` keeps a second card's corner and size apart from the first's:
    /// on an iPad the page and the simulator float at once, and sharing one
    /// corner put them on top of each other. `start` is where a card goes
    /// before it has ever been moved.
    init(size: CGSize, glyph: String, label: String, closeLabel: String, keyboardUp: Bool,
         place: String = "", start: Corner = .topTrailing,
         onOpen: @escaping () -> Void, onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.size = size
        self.glyph = glyph
        self.label = label
        self.closeLabel = closeLabel
        self.keyboardUp = keyboardUp
        self.onOpen = onOpen
        self.onClose = onClose
        self.content = content()
        _corner = AppStorage(wrappedValue: start.rawValue, "mirror.pip.corner\(place)")
        _scale = AppStorage(wrappedValue: 1.0, "mirror.pip.scale\(place)")
    }
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    /// The pinch under way, as a factor on `scale`; 1 between pinches.
    @State private var pinch: CGFloat = 1
    @State private var pinching = false

    /// The card pinched to `times` its base size: from as it comes to two and a
    /// half times that; the room there is caps it further (see body).
    static func enlarged(_ size: CGSize, times: CGFloat) -> CGSize {
        let t = Self.clampedScale(times)
        return CGSize(width: (size.width * t).rounded(), height: (size.height * t).rounded())
    }

    static func clampedScale(_ times: CGFloat) -> CGFloat {
        guard times.isFinite else { return 1 }
        return min(2.5, max(1, times))
    }

    enum Corner: String, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var top: Bool { self == .topLeading || self == .topTrailing }
        var leading: Bool { self == .topLeading || self == .bottomLeading }
        var raised: Corner { leading ? .topLeading : .topTrailing }
    }

    /// The card for a picture of these proportions (width over height): the
    /// same shape as what it shows, its longer side a fixed length, and never
    /// so thin that it cannot be tapped. With no picture yet, `fallback`.
    static func cardSize(aspect: CGFloat?, fallback: CGSize, long: CGFloat = 200) -> CGSize {
        guard let aspect, aspect.isFinite, aspect > 0 else { return fallback }
        // Between a very tall phone and a very wide window; past that it is cut.
        let a = min(max(aspect, 0.42), 2.4)
        // A tall picture gets a little more length: it is narrow.
        let tall = (long * 1.15).rounded()
        return a >= 1
            ? CGSize(width: long, height: (long / a).rounded())
            : CGSize(width: (tall * a).rounded(), height: tall)
    }

    /// Where the card's centre rests for a corner, in a space of `box`.
    static func rest(_ corner: Corner, card: CGSize, in box: CGSize, inset: CGFloat = 12) -> CGPoint {
        CGPoint(x: corner.leading ? inset + card.width / 2 : box.width - inset - card.width / 2,
                y: corner.top ? inset + card.height / 2 : box.height - inset - card.height / 2)
    }

    /// The corner nearest a point: where a card let go of there settles.
    static func nearest(_ p: CGPoint, in box: CGSize) -> Corner {
        switch (p.x < box.width / 2, p.y < box.height / 2) {
        case (true, true): .topLeading
        case (false, true): .topTrailing
        case (true, false): .bottomLeading
        case (false, false): .bottomTrailing
        }
    }

    var body: some View {
        GeometryReader { geo in
            // As big as it was pinched to, but never bigger than the room there
            // is (a short conversation area with the keyboard up, a small phone).
            let wanted = Self.enlarged(size, times: CGFloat(scale) * pinch)
            let fit = min(1, (geo.size.height - 24) / wanted.height, (geo.size.width - 24) / wanted.width)
            let card = CGSize(width: wanted.width * max(0.5, fit), height: wanted.height * max(0.5, fit))
            let saved = Corner(rawValue: corner) ?? .topTrailing
            let at = keyboardUp ? saved.raised : saved
            let home = Self.rest(at, card: card, in: geo.size)
            face
                .frame(width: card.width, height: card.height)
                .scaleEffect(dragging ? 1.04 : 1)
                .position(x: home.x + drag.width, y: home.y + drag.height)
                // Ahead of the card's own tap: a drag that starts on the
                // picture moves it, and only a still tap opens it.
                // Two fingers make it bigger or smaller, and it stays so.
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { v in
                            pinch = v
                            if !pinching { pinching = true; drag = .zero }
                        }
                        .onEnded { v in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                scale = Double(Self.clampedScale(CGFloat(scale) * v))
                                pinch = 1
                            }
                            pinching = false
                            Haptics.tap()
                        }
                )
                // From the first touch, not after a few points: the card sits
                // over the conversation's scroll view, whose own pan takes any
                // touch that has moved a little and is not yet claimed. Claimed
                // at once, the card follows the finger; a touch that never
                // moves is a tap, told apart here, since the buttons under
                // this gesture never see a real touch (VoiceOver still finds
                // them).
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { g in
                            // A second finger landing turns a drag into a pinch.
                            if pinching { return }
                            drag = g.translation
                            if !dragging, hypot(g.translation.width, g.translation.height) > 4 {
                                withAnimation(.easeOut(duration: 0.12)) { dragging = true }
                            }
                        }
                        .onEnded { g in
                            if pinching {
                                withAnimation(.easeOut(duration: 0.12)) { drag = .zero; dragging = false }
                                return
                            }
                            if hypot(g.translation.width, g.translation.height) < 6 {
                                withAnimation(.easeOut(duration: 0.12)) { drag = .zero; dragging = false }
                                // A tap: on the × in the corner, or on the picture.
                                let left = home.x - card.width / 2, top = home.y - card.height / 2
                                let onClose = g.startLocation.x - left < 36 && g.startLocation.y - top < 36
                                if onClose { self.onClose() } else { onOpen() }
                                return
                            }
                            // Where it was heading, not only where it was let go:
                            // a flick across the screen gets there.
                            let landed = CGPoint(x: home.x + g.predictedEndTranslation.width,
                                                 y: home.y + g.predictedEndTranslation.height)
                            let next = Self.nearest(landed, in: geo.size)
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                                corner = next.rawValue
                                drag = .zero
                                dragging = false
                            }
                            Haptics.tap()
                        }
                )
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: keyboardUp)
        }
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack(alignment: .topLeading) {
            Button(action: onOpen) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        // What it is, on a shade so it reads over any page.
                        HStack(spacing: 4) {
                            Image(systemName: glyph).font(.system(size: 9, weight: .semibold))
                            Text(label).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 6)
                        .background(
                            LinearGradient(colors: [.clear, .black.opacity(0.62)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    }
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full screen")
            .accessibilityHint(label)
            .accessibilityIdentifier("mirror-pip")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.5), in: Circle())
                    // A finger's worth of target around a small mark.
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)
        }
        .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}
