import SwiftUI
import UIKit

@main
struct SuperAgentApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase
    /// The chosen accent. Theme reads UserDefaults at render time; this is what
    /// makes a change render NOW — the root re-identifies and everything below
    /// re-evaluates with the new colour.
    @AppStorage("accent") private var accent = ""
    /// Something was shared into the inbox; ask where it should go.
    @State private var shareInboxShown = false


    /// Shares the sheet aimed but could not deliver (Mac unreachable at the
    /// time): send them now, silently — the user already said where.
    private func deliverQueuedShares() {
        for item in ShareInbox.items() {
            guard let machineId = item.machineId, let workspaceId = item.workspaceId,
                  let machine = app.machines.first(where: { $0.id == machineId }) else { continue }
            let conn = app.connection(for: machine)
            conn.connect()
            // Read the picture BEFORE removing — remove deletes the file too,
            // and a failed send must be able to put the whole item back.
            let imageData = ShareInbox.imageData(item)
            ShareInbox.remove(item)
            Task {
                let images: [(mediaType: String, data: Data)] =
                    imageData.map { [(mediaType: "image/jpeg", data: $0)] } ?? []
                let note = item.note ?? ""
                let text = note.isEmpty ? item.text : (item.text.isEmpty ? note : note + "\n\n" + item.text)
                let target: String
                if let chatId = item.chatId {
                    target = chatId
                } else {
                    guard let created = try? await conn.createChat(workspaceId: workspaceId) else {
                        // The Mac is still away; requeue whole for next launch.
                        ShareInbox.save(text: item.text, imageData: imageData, destination: item)
                        return
                    }
                    target = created
                }
                conn.sendMessage(chatId: target, text: text, images: images)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-scrollHarness") {
                    NavigationStack { ChatHarness() }
                } else if ProcessInfo.processInfo.arguments.contains("-sidebarHarness") {
                    // The real RootView, with a made-up Mac behind it: the point
                    // is to look at the actual layout, not a copy of it.
                    RootView().onAppear { app.useHarness() }
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
                .id(accent)
                .environment(app)
                .onAppear { PushDelegate.app = app }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        PushDelegate.app = app
                        app.becameActive()
                        deliverQueuedShares()
                        // Only undecided items ask; anything the share sheet
                        // already aimed goes out above without a question.
                        if app.selected != nil && ShareInbox.items().contains(where: { $0.workspaceId == nil }) {
                            shareInboxShown = true
                        }
                    case .background: app.wentToBackground()
                    default: break
                    }
                }
                .sheet(isPresented: $shareInboxShown) {
                    if let machine = app.selected {
                        ShareInboxSheet(connection: app.connection(for: machine))
                    }
                }
        }
    }
}
