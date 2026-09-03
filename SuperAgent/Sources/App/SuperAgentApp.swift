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
                        // Only when there is somewhere to send it — with no Mac
                        // paired yet, the items just wait in the inbox.
                        if app.selected != nil && !ShareInbox.items().isEmpty { shareInboxShown = true }
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
