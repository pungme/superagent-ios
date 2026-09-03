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
                    case .background: app.wentToBackground()
                    default: break
                    }
                }
        }
    }
}
