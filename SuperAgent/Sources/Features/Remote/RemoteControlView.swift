import SwiftUI
import UIKit
import LocalAuthentication

/// Control this Mac: the phone as its screen, trackpad and keyboard.
///
/// The flow, one idea at a time: Start (Face ID) → "Allow it on the Mac" (the Mac
/// asks someone AT the Mac, and nothing here can answer for them) → type the code
/// the Mac shows → the Mac's screen, with End session always on top of it.
///
/// Two layouts of the same session. One screen: the Mac fitted to the display,
/// touch or trackpad, the keyboard on demand. Half-folded Duo (a laptop): the top
/// screen is the Mac, the bottom screen its keyboard and a trackpad.
struct RemoteControlView: View {
    let connection: Connection
    var onClose: () -> Void

    @State private var controller = RemoteController()
    @State private var posture = PostureWatch()
    @State private var working = false
    @State private var error: String?
    @State private var code = ""
    @State private var notice: String?
    @State private var typing = false
    @AppStorage("remote.controlMode") private var modeRaw = PageControlMode.touch.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var codeFocused: Bool

    private var remote: WireRemote? { connection.remote }
    private var mode: PageControlMode { PageControlMode(rawValue: modeRaw) ?? .touch }
    private var active: Bool { connection.state == .connected && remote?.state == .active }
    private var paused: Bool { remote?.paused != nil }

    var body: some View {
        ZStack {
            Theme.content.ignoresSafeArea()
            Group {
                if connection.state != .connected {
                    message(icon: "wifi.slash", title: "Not connected to your Mac",
                            text: "The session ended with the connection. Start again when your Mac is back.",
                            button: "Close", action: onClose)
                } else {
                    switch remote?.state ?? .idle {
                    case .idle: start
                    case .asking: asking
                    case .code: codeEntry
                    case .active: session
                    }
                }
            }
        }
        .background(PostureReader(watch: posture))
        .overlay(alignment: .top) {
            if let notice {
                Text(notice)
                    .superFont(13, weight: .medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 56).padding(.horizontal, 20)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: notice)
        .task {
            #if DEBUG
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-remotePosture"),
               ProcessInfo.processInfo.arguments.count > i + 1, ProcessInfo.processInfo.arguments[i + 1] == "laptop" {
                posture.force(.laptop)
            }
            #endif
            controller.onNotice = { text in
                notice = text
                Task { try? await Task.sleep(for: .seconds(3.5)); if notice == text { notice = nil } }
            }
            controller.pump.send = { [connection] actions in try await connection.remoteInput(actions) }
        }
        .task(id: active) {
            // While a session runs: say we are here, and how wide a picture is wanted.
            guard active else { return }
            await heartbeat()
        }
        .onChange(of: scenePhase) { _, phase in
            guard active else { return }
            Task { try? await connection.remoteView(visible: phase == .active, key: phase == .active) }
        }
        .onChange(of: paused) { _, p in controller.enabled = !p }
        .onChange(of: remote?.state) { _, s in
            if s != .active { typing = false; controller.stop() }
            if s == .code { codeFocused = true }
        }
        .onDisappear {
            // Leaving the screen is leaving the session: nothing is left running on the Mac.
            if active { Task { try? await connection.remoteEnd() } }
            controller.stop()
            connection.remoteScreen.stop()
        }
        .alert("Remote control", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    // MARK: the steps

    private var start: some View {
        VStack(spacing: 0) {
            closeBar()
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "display").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.textSecondary)
                Text("Control this Mac").superFont(24, weight: .semibold)
                Text("Use your phone as this Mac's screen, trackpad and keyboard. Each time, the Mac asks you to allow it, so you need to be at the Mac.")
                    .superFont(15).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                if let why = RemoteWords.ended(remote?.ended) {
                    Text(why).superFont(14, weight: .medium).multilineTextAlignment(.center)
                        .padding(12).frame(maxWidth: .infinity)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let note = remote?.note, !note.isEmpty {
                    Text(note).superFont(13).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                Button(action: begin) {
                    HStack { if working { ProgressView().controlSize(.small) }; Text("Start") }
                        .superFont(16, weight: .semibold).frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || (remote?.note ?? "").isEmpty == false)
                .accessibilityIdentifier("remote-start")
            }
            .frame(maxWidth: 420).padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
    }

    private var asking: some View {
        VStack(spacing: 0) {
            closeBar(withdraw: true)
            Spacer()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Allow it on the Mac").superFont(22, weight: .semibold)
                Text("A window on your Mac asks if you want to allow this phone. Choose Allow there. It cannot be answered from here.")
                    .superFont(15).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420).padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 0) {
            closeBar(withdraw: true)
            Spacer()
            VStack(spacing: 16) {
                Text("Type the code on the Mac").superFont(22, weight: .semibold)
                Text("The Mac is showing six digits.")
                    .superFont(15).foregroundStyle(Theme.textSecondary)
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .focused($codeFocused)
                    .padding(.vertical, 10)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        if digits.count == 6 { submit(digits) }
                    }
                    .accessibilityIdentifier("remote-code")
                if let left = remote?.triesLeft, left < 3 {
                    Text("\(left) \(left == 1 ? "try" : "tries") left").superFont(13).foregroundStyle(Theme.needsYou)
                }
            }
            .frame(maxWidth: 360).padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
        .onAppear { codeFocused = true }
    }

    /// The way out. While a request is waiting at the Mac it also withdraws it (the Mac's questions close).
    private func closeBar(withdraw: Bool = false) -> some View {
        HStack {
            Button {
                if withdraw { Task { try? await connection.remoteEnd() } }
                onClose()
            } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40).background(Theme.panel, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func message(icon: String, title: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text(title).superFont(20, weight: .semibold)
            Text(text).superFont(15).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    // MARK: asking the Mac

    private func begin() {
        guard !working else { return }
        working = true
        code = ""
        Task {
            defer { working = false }
            switch await FaceID.confirm(connection: connection) {
            case .ok: break
            case .cancelled: return
            case .unavailable(let why), .failed(let why): error = why; return
            }
            do { try await connection.remoteRequest() } catch { self.error = error.localizedDescription }
        }
    }

    private func submit(_ digits: String) {
        Task {
            do { try await connection.remoteCode(digits) } catch {
                self.error = error.localizedDescription
                code = ""
            }
        }
    }

    // MARK: the session

    @ViewBuilder private var session: some View {
        Group {
            if posture.posture == .laptop { laptopLayout } else { singleLayout }
        }
        .onAppear {
            connection.remoteScreen.start(
                handler: { [controller] u in MainActor.assumeIsolated { controller.deliver(u) } },
                needKey: { [connection] in Task { @MainActor in try? await connection.remoteView(key: true) } })
            controller.onNeedPicture = { [connection] in Task { try? await connection.remoteView(key: true) } }
        }
    }

    /// Said to the Mac every few seconds: the phone is here, and the screen is up.
    private func heartbeat() async {
        var first = true
        while !Task.isCancelled {
            let visible = scenePhase == .active
            let width = controller.wantedWidth
            try? await connection.remoteView(visible: visible, maxWidth: width, key: first ? true : nil)
            first = false
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private var endButton: some View {
        Button {
            Task { try? await connection.remoteEnd() }
        } label: {
            Text("End session").superFont(13, weight: .semibold).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(red: 0.78, green: 0.16, blue: 0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("remote-end")
    }

    private var screenWithPause: some View {
        RemoteSurface(controller: controller, trackpad: mode == .trackpad && posture.posture != .laptop)
            .overlay { if let r = remote, r.paused != nil { pausedCover(r) } }
    }

    private func pausedCover(_ r: WireRemote) -> some View {
        ZStack {
            Theme.content
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(Theme.textSecondary)
                Text("Paused").superFont(17, weight: .semibold)
                Text(RemoteWords.paused(r.paused, by: r.pausedBy))
                    .superFont(14).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .accessibilityIdentifier("remote-paused")
    }

    // MARK: layouts

    private var singleLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                endButton
                Spacer()
                Picker("Pointer", selection: $modeRaw) {
                    Text("Touch").tag(PageControlMode.touch.rawValue)
                    Text("Trackpad").tag(PageControlMode.trackpad.rawValue)
                }
                .pickerStyle(.segmented).frame(maxWidth: 190)
                Button { typing.toggle() } label: {
                    Image(systemName: typing ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.system(size: 17, weight: .medium)).frame(width: 40, height: 34)
                }
                .buttonStyle(.plain).accessibilityLabel(typing ? "Hide keyboard" : "Keyboard")
                .accessibilityIdentifier("remote-keyboard")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            screenWithPause
                .background(alignment: .topLeading) {
                    RemoteKeyboardHost(active: $typing, controller: controller)
                        .frame(width: 1, height: 1).opacity(0.01).accessibilityHidden(true)
                }
        }
    }

    /// Half-folded Duo: the top screen is the Mac, the bottom screen is its
    /// keyboard and trackpad, as a laptop's. The two halves of the window are the two screens.
    private var laptopLayout: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack { endButton; Spacer() }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                screenWithPause
            }
            .frame(maxHeight: .infinity)
            Color.black.frame(height: HingeGap.height)
            MacKeyboard(controller: controller)
                .frame(maxHeight: .infinity)
                .background(Color(white: 0.09))
        }
    }
}

/// The room the hinge takes between the two screens of a half-folded Duo, in points.
enum HingeGap {
    static let height: CGFloat = 0
}

// MARK: - Face ID

/// Face ID before each session starts. An extra gate on the PHONE: it opens nothing on
/// the Mac, which still has to be allowed by someone at the Mac.
enum FaceID {
    enum Outcome { case ok, cancelled, unavailable(String), failed(String) }

    @MainActor
    static func confirm(connection: Connection) async -> Outcome {
        #if DEBUG
        if connection.machine.id == "harness" { return .ok }
        #endif
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var err: NSError?
        // Face ID, or the passcode when it will not read. A phone with neither cannot be told apart from anyone's.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return .unavailable("Set a passcode on this phone to use it as a remote for your Mac.")
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Control your Mac from this phone")
            return ok ? .ok : .cancelled
        } catch let e as LAError where [.userCancel, .systemCancel, .appCancel].contains(e.code) {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
