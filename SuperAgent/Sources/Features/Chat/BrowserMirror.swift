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
    /// Paused while the keyboard is up (the pane is collapsed then) or the app is away.
    var paused = false

    @State private var shot: WireBrowserShot?
    @State private var image: UIImage?
    /// The frame we already decoded, by its bytes — comparing images themselves
    /// would mean re-encoding two screenshots on every poll.
    @State private var lastFrame: Int?
    @State private var inFlight = false
    @State private var unavailable: String?
    @State private var url = ""
    @State private var opening = false
    @State private var error: String?
    @FocusState private var urlFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            omnibar
            Group {
                if let image {
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
        .task(id: [paused, scenePhase != .active].description) {
            // Nothing to mirror while the pane is collapsed or the app is away.
            if !paused, scenePhase == .active { await poll() }
        }
        .alert("Browser", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
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
                Button(action: onExpand) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .accessibilityLabel("Open full screen")
            }
            if let onHide {
                Button(action: onHide) { Image(systemName: "chevron.up") }
                    .tint(Theme.textSecondary).accessibilityLabel("Hide the page")
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
            let s = try await connection.browserShot(chatId: chat.id)
            let previous = shot
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
    /// Paused while the keyboard is up or the app is away.
    var paused = false

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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "iphone").superFont(12).foregroundStyle(Theme.textTertiary)
                Text(device).superFont(13).lineLimit(1).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if sending { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.panel)

            screen

            HStack(spacing: 18) {
                Button { Task { await refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).tint(Theme.textSecondary)
                if let onHide {
                    Button(action: onHide) { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain).tint(Theme.textSecondary).accessibilityLabel("Hide the simulator")
                }
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
        .task(id: paused) { await loop() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh(force: true) } } }
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
                        // A tap lands where you put it: the still is the device's
                        // own pixels, so the only maths is undoing scaledToFit.
                        .gesture(
                            SpatialTapGesture().onEnded { t in
                                guard let px = devicePoint(t.location, in: geo.size, image: image) else { return }
                                Task { await tap(px) }
                            }
                        )
                } else if let unavailable {
                    Text(unavailable).superFont(13).foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center).padding()
                } else {
                    ProgressView()
                }
            }
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

    private func loop() async {
        while !Task.isCancelled {
            if paused { return }
            await refresh(force: false)
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

    private func refresh(force: Bool) async {
        guard !inFlight, connection.state == .connected else { return }
        guard force || !paused else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            let s = try await connection.simShot(chatId: chat.id)
            shot = s
            if let comma = s.url.firstIndex(of: ","),
               let data = Data(base64Encoded: String(s.url[s.url.index(after: comma)...])),
               let ui = UIImage(data: data) {
                image = ui
                unavailable = nil
            }
        } catch let e as RpcError {
            unavailable = e.message
        } catch {
            unavailable = "The simulator isn't available right now."
        }
    }
}
