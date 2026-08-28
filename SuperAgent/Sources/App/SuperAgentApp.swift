import SwiftUI

@main
struct SuperAgentApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: app.becameActive()
                    case .background: app.wentToBackground()
                    default: break
                    }
                }
        }
    }
}
