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
    /// Touch or trackpad, remembered across launches.
    @AppStorage("browser.controlMode") private var modeRaw = PageControlMode.touch.rawValue
    private var mode: PageControlMode { PageControlMode(rawValue: modeRaw) ?? .touch }
    /// The keyboard is up, typing into the page.
    @State private var typing = false
    @State private var pump = PageInputPump()
    /// The Mac is from before the page could be used from here.
    @State private var tooOld = false

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
                if let image {
                    // The page to use, not only to look at: tap or point and
                    // click, drag or two fingers to scroll, the keyboard to
                    // type. Full screen, a desktop page fits across and is
                    // small: pinch in (touch) to go close. Docked, it runs
                    // across the strip from the top, as it did.
                    PageSurface(image: image, chatId: chat.id, fitWidth: compact && !expanded,
                                mode: mode, post: post)
                        .overlay(alignment: .bottom) {
                            if tooOld {
                                Text("Update Superagent on the Mac to use the page from here.")
                                    .superFont(12, weight: .medium)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(10)
                                    .transition(.opacity)
                            }
                        }
                        .background(alignment: .topLeading) {
                            PageKeyboard(active: $typing, post: post)
                                .frame(width: 1, height: 1).opacity(0.01)
                                .accessibilityHidden(true)
                        }
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
                .accessibilityLabel("Reload")
            if image != nil {
                modeSwitch
                Button { typing.toggle() } label: {
                    Image(systemName: typing ? "keyboard.chevron.compact.down" : "keyboard")
                }
                .accessibilityLabel(typing ? "Stop typing" : "Type into the page")
            }
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

    /// Touch or trackpad: two small faces in one capsule, the one in use lit.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(PageControlMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { modeRaw = m.rawValue }
                    Haptics.tap()
                } label: {
                    Image(systemName: m == .touch ? "hand.point.up.left" : "cursorarrow")
                        .superFont(compact ? 12 : 14, weight: .medium)
                        .frame(width: compact ? 28 : 34, height: compact ? 22 : 28)
                        .background(mode == m ? Theme.textPrimary : .clear, in: Capsule())
                        .foregroundStyle(mode == m ? Theme.content : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m == .touch ? "Touch" : "Trackpad")
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.hover, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Control the page by")
    }

    private func post(_ input: BrowserInput) {
        if pump.send == nil {
            let connection = connection, chatId = chat.id
            pump.send = { input in try await connection.browserInput(chatId: chatId, input) }
            pump.onUnsupported = {
                withAnimation { tooOld = true }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { tooOld = false }
                }
            }
        }
        pump.post(input)
    }

    // MARK: Mirroring

    /// While the page is changing, refresh briskly; when it settles, back off —
    /// the capture is a whole JPEG through the relay, not a video stream.
    ///
    /// While you are using the page, much faster: what a tap or a scroll did
    /// shows within a quarter of a second, and a touch cuts a long wait short.
    private func poll() async {
        var quiet = 0
        while !Task.isCancelled {
            let changed = await refresh()
            quiet = changed ? 0 : min(quiet + 1, 4)
            let since = pump.lastSent
            let hot = Date().timeIntervalSince(since) < 3
            let wait = hot ? 250 : (changed ? 700 : 700 + quiet * 800)
            var slept = 0
            while slept < wait, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(min(100, wait - slept)))
                slept += 100
                // Touched while waiting: go now, after a moment for the Mac to act.
                if pump.lastSent != since, slept >= 100 { quiet = 0; break }
            }
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
    /// Where the trackpad's pointer is on each conversation's page.
    static var cursor: [String: CGPoint] = [:]
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

// MARK: - Using the page from the phone

/// How a finger works on the mirrored page. Touch: where you tap is where it
/// clicks, a drag scrolls. Trackpad: a pointer on the page that one finger
/// moves, like a laptop's trackpad.
enum PageControlMode: String, CaseIterable {
    case touch, trackpad
}

/// Where the picture of the page is on the phone's screen, and back: the maths
/// between a finger and a point on the page. Points on the page are fractions
/// of the picture (0...1), which is what the Mac takes (`browser.input`).
enum PageMap {
    /// The picture's place in the box, before any zoom: across the whole width
    /// from the top (`fitWidth`, the docked strip, which may run past the
    /// bottom), or all of it, centred across, from the top.
    static func drawn(image: CGSize, in box: CGSize, fitWidth: Bool) -> CGRect {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let s = fitWidth ? box.width / image.width : min(box.width / image.width, box.height / image.height)
        let w = image.width * s, h = image.height * s
        return CGRect(x: (box.width - w) / 2, y: 0, width: w, height: h)
    }

    /// A point of the picture at rest, where it is with the picture zoomed
    /// about the box's centre and moved by `pan` (SimulatorMirror.unzoom, the other way).
    static func zoomed(_ p: CGPoint, in box: CGSize, zoom: CGFloat, pan: CGSize) -> CGPoint {
        let c = CGPoint(x: box.width / 2, y: box.height / 2)
        return CGPoint(x: (p.x - c.x) * zoom + c.x + pan.width, y: (p.y - c.y) * zoom + c.y + pan.height)
    }

    /// The point on the page under a finger, or nil off the picture.
    static func fraction(of p: CGPoint, image: CGSize, box: CGSize, fitWidth: Bool,
                         zoom: CGFloat = 1, pan: CGSize = .zero) -> CGPoint? {
        let r = drawn(image: image, in: box, fitWidth: fitWidth)
        guard r.width > 0, r.height > 0 else { return nil }
        let q = SimulatorMirror.unzoom(p, in: box, zoom: zoom, pan: pan)
        let f = CGPoint(x: (q.x - r.minX) / r.width, y: (q.y - r.minY) / r.height)
        guard (0...1).contains(f.x), (0...1).contains(f.y) else { return nil }
        return f
    }

    /// Where a point on the page is on the screen: where the pointer is drawn.
    static func point(of f: CGPoint, image: CGSize, box: CGSize, fitWidth: Bool,
                      zoom: CGFloat = 1, pan: CGSize = .zero) -> CGPoint {
        let r = drawn(image: image, in: box, fitWidth: fitWidth)
        return zoomed(CGPoint(x: r.minX + f.x * r.width, y: r.minY + f.y * r.height), in: box, zoom: zoom, pan: pan)
    }

    /// A finger's travel on the screen as a fraction of the picture: what a
    /// scroll sends, and how far the page should move to stay under the finger.
    static func travel(_ d: CGSize, image: CGSize, box: CGSize, fitWidth: Bool, zoom: CGFloat = 1) -> CGSize {
        let r = drawn(image: image, in: box, fitWidth: fitWidth)
        guard r.width > 0, r.height > 0, zoom > 0 else { return .zero }
        return CGSize(width: d.width / (r.width * zoom), height: d.height / (r.height * zoom))
    }

    /// The trackpad's acceleration, as on a Mac: a slow finger is precise
    /// (one point for one point), a quick one crosses the page. `speed` in points a second.
    static func gain(speed: CGFloat) -> CGFloat {
        guard speed.isFinite else { return 1 }
        return min(3.5, max(1, 1 + (speed - 120) / 450))
    }

    /// The pointer moved by a finger's travel, held on the page. `span` is the
    /// size, on the screen, that is the whole page: the picture as drawn.
    static func moveCursor(_ c: CGPoint, by d: CGSize, speed: CGFloat, span: CGSize) -> CGPoint {
        guard span.width > 0, span.height > 0 else { return c }
        let g = gain(speed: speed)
        return CGPoint(x: min(1, max(0, c.x + d.width * g / span.width)),
                       y: min(1, max(0, c.y + d.height * g / span.height)))
    }

    /// Whether a tap is the second of a double-click: soon after the last, and close to it.
    static func isSecondClick(at p: CGPoint, after last: (at: CGPoint, time: Date)?, now: Date = .now,
                              within: TimeInterval = 0.35, distance: CGFloat = 0.03) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last.time) < within && hypot(p.x - last.at.x, p.y - last.at.y) < distance
    }
}

/// What the phone sends the page, sent briskly but not wastefully: pointer
/// moves keep only the latest and scrolls add up for one frame (about 30 a
/// second), and anything else (a click, a key, text) goes at once, after
/// whatever was waiting, so the order is the order you did things in.
@MainActor
final class PageInputPump {
    var send: ((BrowserInput) async throws -> Void)?
    /// The Mac is from before `browser.input`.
    var onUnsupported: (() -> Void)?
    /// When the phone last sent anything: the mirror refreshes briskly for a while after.
    private(set) var lastSent: Date = .distantPast

    private var move: CGPoint?
    private var scrollAt: CGPoint?
    private var scroll: CGSize = .zero
    private var text = ""
    private var timer: Task<Void, Never>?

    func post(_ input: BrowserInput) {
        switch input {
        case .move(let p):
            move = p
            schedule()
        case .scroll(let p, let d):
            if move != nil { flushPointer() }
            scrollAt = p
            scroll.width += d.width
            scroll.height += d.height
            schedule()
        case .text(let t):
            flushPointer()
            text += t
            schedule()
        default:
            flush()
            fire(input)
        }
    }

    func flush() {
        timer?.cancel()
        timer = nil
        flushPointer()
        if !text.isEmpty { fire(.text(text)); text = "" }
    }

    private func flushPointer() {
        if !text.isEmpty { fire(.text(text)); text = "" }
        if let m = move { fire(.move(m)); move = nil }
        if let at = scrollAt {
            if abs(scroll.width) > 0.0005 || abs(scroll.height) > 0.0005 { fire(.scroll(at: at, delta: scroll)) }
            scrollAt = nil
            scroll = .zero
        }
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

    private func fire(_ input: BrowserInput) {
        lastSent = .now
        guard let send else { return }
        // The request leaves before the first suspension (Connection.rpc), so
        // tasks started in order put their frames on the socket in order.
        Task { [weak self] in
            do { try await send(input) } catch let e as RpcError where e.code == "bad-params" && e.message.contains("unknown method") {
                self?.onUnsupported?()
            } catch {}
        }
    }
}

/// The mirrored page as something to use: the picture, the pointer in
/// trackpad mode, and every gesture turned into what the page should get.
struct PageSurface: View {
    let image: UIImage
    let chatId: String
    /// The docked strip: the page across its width, from the top.
    let fitWidth: Bool
    let mode: PageControlMode
    let post: (BrowserInput) -> Void

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var cursor = CGPoint(x: 0.5, y: 0.5)
    @State private var holding = false
    @State private var lastClick: (at: CGPoint, time: Date)?
    @State private var scrollAt: CGPoint?
    @State private var glide: Task<Void, Never>?
    /// A tap's mark, briefly, where it landed: so you see it was taken.
    @State private var ripple: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            let r = PageMap.drawn(image: image.size, in: box, fitWidth: fitWidth)
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(uiImage: image)
                    .resizable()
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .scaleEffect(zoom)
            .offset(pan)
            .overlay(alignment: .topLeading) {
                if let ripple {
                    Circle().stroke(Theme.accent, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .position(ripple)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if mode == .trackpad {
                    PagePointer(pressed: holding)
                        .offset(x: PageMap.point(of: cursor, image: image.size, box: box, fitWidth: fitWidth,
                                                 zoom: zoom, pan: pan).x,
                                y: PageMap.point(of: cursor, image: image.size, box: box, fitWidth: fitWidth,
                                                 zoom: zoom, pan: pan).y)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay {
                PageGestures(trackpad: mode == .trackpad) { event in
                    handle(event, box: box, drawn: r)
                }
            }
        }
        .onAppear { if let c = MirrorFrames.cursor[chatId] { cursor = c } }
        .onChange(of: cursor) { _, c in MirrorFrames.cursor[chatId] = c }
        .onChange(of: mode) { _, _ in
            // The pointer works on the page as it fits; a pinched-in picture is touch's.
            withAnimation(.spring(response: 0.3)) { zoom = 1; pan = .zero }
            if holding { post(.up(cursor)); holding = false }
        }
        .onDisappear {
            glide?.cancel()
            if holding { post(.up(cursor)); holding = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The page on the Mac")
        .accessibilityHint(mode == .touch ? "Tap to click, drag to scroll" : "Trackpad: move the pointer, tap to click")
    }

    private func at(_ p: CGPoint, _ box: CGSize) -> CGPoint? {
        PageMap.fraction(of: p, image: image.size, box: box, fitWidth: fitWidth, zoom: zoom, pan: pan)
    }

    private func click(_ f: CGPoint, right: Bool, mark: CGPoint?) {
        let second = !right && PageMap.isSecondClick(at: f, after: lastClick)
        post(.click(f, right: right, count: second ? 2 : 1))
        lastClick = second || right ? nil : (f, .now)
        Haptics.tap()
        if let mark {
            withAnimation(.easeOut(duration: 0.12)) { ripple = mark }
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.easeOut(duration: 0.2)) { ripple = nil }
            }
        }
    }

    private func handle(_ e: PageGestureEvent, box: CGSize, drawn r: CGRect) {
        switch e {
        case .tap(let p, let fingers):
            glide?.cancel()
            if mode == .touch {
                guard let f = at(p, box) else { return }
                click(f, right: fingers > 1, mark: p)
            } else {
                click(cursor, right: fingers > 1, mark: nil)
            }
        case .pan(let state, let p, let d, let v, let fingers):
            if state == .began { glide?.cancel() }
            if mode == .touch {
                if zoom > 1, fingers == 1 {
                    // Pinched in: one finger moves the picture, as it does at the Mac's photos.
                    pan = SimulatorMirror.clampPan(CGSize(width: pan.width + d.width, height: pan.height + d.height),
                                                   in: box, zoom: zoom)
                    return
                }
                if state == .began { scrollAt = at(p, box) ?? CGPoint(x: 0.5, y: 0.5) }
                scrollBy(d, at: scrollAt ?? CGPoint(x: 0.5, y: 0.5), box: box)
                if state == .ended { fling(v, at: scrollAt ?? CGPoint(x: 0.5, y: 0.5), box: box) }
            } else if fingers >= 2 {
                // Two fingers scroll under the pointer, the page following them.
                scrollBy(d, at: cursor, box: box)
                if state == .ended { fling(v, at: cursor, box: box) }
            } else {
                let next = PageMap.moveCursor(cursor, by: d, speed: hypot(v.x, v.y),
                                              span: CGSize(width: r.width * zoom, height: r.height * zoom))
                if next != cursor {
                    cursor = next
                    post(.move(next))
                }
            }
        case .hold(let state):
            // Tap, then touch again and hold: the button stays down while the
            // finger moves (select text, drag a slider), up when it lifts.
            guard mode == .trackpad else { return }
            if state == .began, !holding {
                holding = true
                post(.down(cursor))
                Haptics.tap()
            } else if state == .ended || state == .cancelled || state == .failed, holding {
                holding = false
                post(.up(cursor))
            }
        case .pinch(let state, let scale):
            guard mode == .touch else { return }
            zoom = min(5, max(1, zoom * scale))
            pan = SimulatorMirror.clampPan(pan, in: box, zoom: zoom)
            if state == .ended, zoom <= 1.02 {
                withAnimation(.spring(response: 0.3)) { zoom = 1; pan = .zero }
            }
        }
    }

    private func scrollBy(_ d: CGSize, at f: CGPoint, box: CGSize) {
        let t = PageMap.travel(d, image: image.size, box: box, fitWidth: fitWidth, zoom: zoom)
        if t != .zero { post(.scroll(at: f, delta: t)) }
    }

    /// Let go mid-swipe: the page carries on and slows, as a flicked page does.
    private func fling(_ v: CGPoint, at f: CGPoint, box: CGSize) {
        var step = CGSize(width: v.x / 60, height: v.y / 60)
        guard hypot(step.width, step.height) > 3 else { return }
        glide = Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                step = CGSize(width: step.width * 0.9, height: step.height * 0.9)
                if hypot(step.width, step.height) < 0.6 { return }
                scrollBy(step, at: f, box: box)
            }
        }
    }
}

/// The pointer drawn over the page in trackpad mode: the Mac's own arrow, its
/// tip on the point the next click lands on.
private struct PagePointer: View {
    var pressed: Bool

    var body: some View {
        ArrowShape()
            .fill(Color.black)
            .overlay(ArrowShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)))
            .frame(width: 14, height: 21)
            .scaleEffect(pressed ? 0.85 : 1, anchor: .topLeading)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }

    private struct ArrowShape: Shape {
        func path(in r: CGRect) -> Path {
            let sx = r.width / 14, sy = r.height / 21
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
            var path = Path()
            path.move(to: p(0, 0))
            path.addLine(to: p(0, 17))
            path.addLine(to: p(4.2, 13.2))
            path.addLine(to: p(7, 20))
            path.addLine(to: p(9.8, 18.8))
            path.addLine(to: p(7.1, 12.3))
            path.addLine(to: p(12.8, 12.3))
            path.closeSubpath()
            return path
        }
    }
}

enum PageGestureEvent {
    case tap(CGPoint, fingers: Int)
    /// `delta`: travel since the last change; `velocity` in points a second.
    case pan(UIGestureRecognizer.State, CGPoint, delta: CGSize, velocity: CGPoint, fingers: Int)
    case hold(UIGestureRecognizer.State)
    /// `scale`: since the last change.
    case pinch(UIGestureRecognizer.State, scale: CGFloat)
}

/// UIKit's recognisers over the page: SwiftUI has no two-finger tap or
/// two-finger pan, which the trackpad's right-click and scroll are.
private struct PageGestures: UIViewRepresentable {
    var trackpad: Bool
    var handle: (PageGestureEvent) -> Void

    func makeUIView(context: Context) -> PageGestureView { PageGestureView() }

    func updateUIView(_ view: PageGestureView, context: Context) {
        view.handle = handle
        view.trackpad = trackpad
    }
}

final class PageGestureView: UIView, UIGestureRecognizerDelegate {
    var handle: ((PageGestureEvent) -> Void)?
    var trackpad = false { didSet { if trackpad != oldValue { configure() } } }

    private let tap1 = UITapGestureRecognizer()
    private let tap2 = UITapGestureRecognizer()
    private let pan1 = UIPanGestureRecognizer()
    private let pan2 = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let hold = UILongPressGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        tap2.numberOfTouchesRequired = 2
        pan1.maximumNumberOfTouches = 1
        pan2.minimumNumberOfTouches = 2
        pan2.maximumNumberOfTouches = 2
        // Tap, then touch again and stay: a held button. Not on a quick second
        // tap, which is a double-click.
        hold.numberOfTapsRequired = 1
        hold.minimumPressDuration = 0.18
        hold.allowableMovement = .greatestFiniteMagnitude
        tap1.addTarget(self, action: #selector(onTap(_:)))
        tap2.addTarget(self, action: #selector(onTap(_:)))
        pan1.addTarget(self, action: #selector(onPan(_:)))
        pan2.addTarget(self, action: #selector(onPan(_:)))
        pinch.addTarget(self, action: #selector(onPinch(_:)))
        hold.addTarget(self, action: #selector(onHold(_:)))
        for g in [tap1, tap2, pan1, pan2, pinch, hold] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
        // One finger's tap waits for two: a two-finger tap is not also two clicks.
        tap1.require(toFail: tap2)
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        pan2.isEnabled = trackpad
        hold.isEnabled = trackpad
        pinch.isEnabled = !trackpad
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The held button and the finger moving it are one gesture; so are a pinch and its pan.
        (g == hold || other == hold) || (g == pinch || other == pinch)
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        handle?(.tap(g.location(in: self), fingers: g.numberOfTouchesRequired))
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        let v = g.velocity(in: self)
        handle?(.pan(g.state, g.location(in: self), delta: CGSize(width: t.x, height: t.y),
                     velocity: v, fingers: g == pan2 ? 2 : 1))
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        let s = g.scale
        g.scale = 1
        handle?(.pinch(g.state, scale: s))
    }

    @objc private func onHold(_ g: UILongPressGestureRecognizer) {
        handle?(.hold(g.state))
    }
}

/// Typing into the page: a responder that takes the keyboard and hands each
/// key on as it is pressed, keeping no text of its own (the text is on the
/// page). Over it, a row of the keys a phone's keyboard lacks.
struct PageKeyboard: UIViewRepresentable {
    @Binding var active: Bool
    var post: (BrowserInput) -> Void

    func makeUIView(context: Context) -> PageKeyCatcher {
        let v = PageKeyCatcher()
        v.onDone = { active = false }
        return v
    }

    func updateUIView(_ v: PageKeyCatcher, context: Context) {
        v.post = post
        v.onDone = { active = false }
        if active, !v.isFirstResponder {
            DispatchQueue.main.async { v.becomeFirstResponder() }
        } else if !active, v.isFirstResponder {
            DispatchQueue.main.async { v.resignFirstResponder() }
        }
    }
}

final class PageKeyCatcher: UIView, UIKeyInput {
    var post: ((BrowserInput) -> Void)?
    var onDone: (() -> Void)?

    // What the page gets is what was pressed: no corrections the page never sees.
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }

    func insertText(_ text: String) {
        switch text {
        case "\n": post?(.key("Enter"))
        case "\t": post?(.key("Tab"))
        default: post?(.text(text))
        }
    }

    func deleteBackward() { post?(.key("Backspace")) }

    private lazy var strip: UIView = {
        let host = UIHostingController(rootView: PageKeyStrip(press: { [weak self] key in
            self?.post?(.key(key))
        }, done: { [weak self] in
            _ = self?.resignFirstResponder()
            self?.onDone?()
        }))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
        bar.allowsSelfSizing = false
        bar.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: bar.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])
        hostRef = host
        return bar
    }()
    private var hostRef: UIViewController?

    override var inputAccessoryView: UIView? { strip }

    /// A hardware keyboard (an iPad's): the keys UIKeyInput does not hand on.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for press in presses {
            guard let k = press.key else { rest.insert(press); continue }
            let shift = k.modifierFlags.contains(.shift)
            let name: String? = switch k.keyCode {
            case .keyboardLeftArrow: "ArrowLeft"
            case .keyboardRightArrow: "ArrowRight"
            case .keyboardUpArrow: "ArrowUp"
            case .keyboardDownArrow: "ArrowDown"
            case .keyboardEscape: "Escape"
            case .keyboardHome: "Home"
            case .keyboardEnd: "End"
            case .keyboardPageUp: "PageUp"
            case .keyboardPageDown: "PageDown"
            case .keyboardDeleteForward: "Delete"
            case .keyboardTab where shift: "Tab"
            default: nil
            }
            if let name { post?(.key(name, shift: shift)) } else { rest.insert(press) }
        }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }
}

/// The keys over the keyboard while typing into the page.
private struct PageKeyStrip: View {
    var press: (String) -> Void
    var done: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            key("esc", "Escape")
            key("tab", "Tab")
            Spacer(minLength: 2)
            key(Image(systemName: "arrow.left"), "ArrowLeft", label: "Left")
            key(Image(systemName: "arrow.up"), "ArrowUp", label: "Up")
            key(Image(systemName: "arrow.down"), "ArrowDown", label: "Down")
            key(Image(systemName: "arrow.right"), "ArrowRight", label: "Right")
            Spacer(minLength: 2)
            key(Image(systemName: "return"), "Enter", label: "Return")
            Button(action: done) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Stop typing")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func key(_ text: String, _ name: String) -> some View {
        key(Text(text).font(.system(size: 13, weight: .medium)), name, label: name)
    }

    private func key<L: View>(_ face: L, _ name: String, label: String) -> some View {
        Button { press(name); UIDevice.current.playInputClick() } label: {
            face
                .font(.system(size: 14, weight: .medium))
                .frame(minWidth: 36, minHeight: 34)
                .padding(.horizontal, 2)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}

extension PageKeyCatcher: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
