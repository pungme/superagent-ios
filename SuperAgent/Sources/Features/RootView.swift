import SwiftUI
import os

private let log = Logger(subsystem: "dev.superagent.ios", category: "app")

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var showPair = false
    @State private var showSettings = false
    /// A pairing link opened from outside (AirDrop, Messages, a tapped QR) skips the scanner.
    @State private var incomingPair: PairPayload?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let machine = app.selected {
                    MachineHomeView(connection: app.connection(for: machine))
                } else {
                    WelcomeView(onPair: { showPair = true })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showPair) { PairView() }
        // item-based, so the sheet always sees the payload that opened it.
        .sheet(item: $incomingPair) { payload in PairView(initial: payload) }
        .sheet(isPresented: $showSettings) { SettingsView(onPair: { showSettings = false; showPair = true }) }
        // A tapped notification lands on its conversation.
        .onChange(of: app.openChatId, initial: true) { _, _ in openPending() }
        .onChange(of: app.chatsVersion) { _, _ in openPending() }
        .onOpenURL { url in
            log.info("open url \(url.absoluteString.prefix(40), privacy: .public)")
            guard let payload = PairPayload.parse(url.absoluteString) else { log.error("pair link did not parse"); return }
            showSettings = false
            showPair = false
            incomingPair = payload
        }
    }
}

extension RootView {
    /// Navigate to the chat a notification named, once its Mac has told us about it.
    private func openPending() {
        guard let chatId = app.openChatId, let machine = app.selected else { return }
        let c = app.connection(for: machine)
        guard let chat = c.chats.first(where: { $0.id == chatId }),
              let ws = c.tree.flatMap(\.workspaces).first(where: { $0.id == chat.workspaceId }) else { return }
        path = NavigationPath()
        path.append(ws)
        path.append(chat)
        app.openChatId = nil
    }
}

struct WelcomeView: View {
    var onPair: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Your Mac, in your pocket")
                .font(.title2.bold())
            Text("Follow the agent, send it work, approve what it asks — from anywhere. Pair once; no accounts, no setup.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Spacer()
            Button(action: onPair) {
                Text("Pair a Mac")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            Text("On the Mac: Settings → Phone → Show pairing code")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .navigationTitle("SuperAgent")
    }
}
