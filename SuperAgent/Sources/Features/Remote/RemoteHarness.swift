#if DEBUG
import SwiftUI

/// Control this Mac with a made-up Mac behind it, to look at every state and both
/// layouts without pairing anything. Launch with `-remoteHarness`, then
/// `-remoteState idle|asking|code|active|paused|ended` and, to see the Duo's
/// laptop layout on any device, `-remotePosture laptop`. The code is 123456.
struct RemoteHarness: View {
    @State private var connection = Connection.sidebarHarness()

    var body: some View {
        RemoteControlView(connection: connection, onClose: {})
            .task {
                connection.harnessConnected()
                let args = ProcessInfo.processInfo.arguments
                let state = args.firstIndex(of: "-remoteState").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil } ?? "idle"
                switch state {
                case "asking": connection.harnessSetRemote(WireRemote(available: true, state: .asking))
                case "code": connection.harnessSetRemote(WireRemote(available: true, state: .code, triesLeft: 3))
                case "active": connection.harnessStartScreen()
                case "paused": connection.harnessStartScreen(paused: true)
                case "ended": connection.harnessSetRemote(WireRemote(available: true, state: .idle, ended: "idle"))
                default: connection.harnessSetRemote(WireRemote(available: true, state: .idle))
                }
            }
    }
}
#endif
