import Foundation
import Observation
import SwiftUI

/// The app's root: paired Macs and a live connection to each while we're on screen.
@MainActor
@Observable
final class AppState {
    private(set) var machines: [PairedMachine] = MachineStore.load()
    private(set) var connections: [String: Connection] = [:]
    var selectedMachineId: String?
    var pushToken: String?

    /// The composer's Model / Mode pills, remembered like the desktop's.
    var preferredModel: String = UserDefaults.standard.string(forKey: "composer.model") ?? "" {
        didSet { UserDefaults.standard.set(preferredModel, forKey: "composer.model") }
    }
    var preferredMode: String = UserDefaults.standard.string(forKey: "composer.mode") ?? "bypassPermissions" {
        didSet { UserDefaults.standard.set(preferredMode, forKey: "composer.mode") }
    }

    var selected: PairedMachine? {
        machines.first { $0.id == selectedMachineId } ?? machines.first
    }

    init() {
        selectedMachineId = machines.first?.id
    }

    #if DEBUG
    /// Put a made-up Mac in front of the real RootView, so the layout can be
    /// looked at — on a phone or an iPad — without pairing anything.
    func useHarness() {
        // An explicit flag wins even on a phone with a real Mac paired: the
        // point is to look at the app with known contents. Nothing here is
        // written to disk — MachineStore is only touched by add/remove — so the
        // real pairing is still there next launch.
        guard !machines.contains(where: { $0.id == "harness" }) else { return }
        let c = Connection.sidebarHarness()
        machines = [c.machine]
        connections[c.machine.id] = c
        selectedMachineId = c.machine.id
        // `-openChat <id>` lands straight in a conversation. Touch injection is
        // not always available on a simulator, and a layout you cannot reach is
        // a layout you cannot check.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-openChat"), i + 1 < args.count { openChatId = args[i + 1] }
    }
    #endif

    func connection(for machine: PairedMachine) -> Connection {
        if let c = connections[machine.id] { return c }
        let c = Connection(machine: machine)
        c.onChatsChanged = { [weak self] in self?.chatsVersion += 1 }
        connections[machine.id] = c
        return c
    }

    // MARK: Foreground / background

    func becameActive() {
        // Notifications only make sense once a Mac is paired — ask then, not on first launch.
        // Not for the harness: it is a made-up Mac, and the prompt lands over
        // whatever is being looked at.
        if !machines.isEmpty, machines.first?.id != "harness" {
            Task { await PushDelegate.requestAuthorization() }
        }
        for m in machines {
            let c = connection(for: m)
            // The harness has no Mac to dial. Left to try, it spends the whole
            // session behind a "could not be found" banner.
            if m.id == "harness" { continue }
            c.connect()
            c.reportPresence(active: true, pushToken: pushToken)
        }
    }

    func wentToBackground() {
        for c in connections.values {
            c.reportPresence(active: false)
            c.disconnect()
        }
    }

    // MARK: Pairing / removal

    func add(_ machine: PairedMachine) {
        // Re-pairing the same Mac changes its secret, token or relay: a cached
        // connection would keep using the old record.
        connections[machine.id]?.disconnect()
        connections[machine.id] = nil
        MachineStore.upsert(machine)
        machines = MachineStore.load()
        selectedMachineId = machine.id
        let c = connection(for: machine)
        c.connect()
        c.reportPresence(active: true, pushToken: pushToken)
        Task { await PushDelegate.requestAuthorization() }
    }

    func remove(_ machine: PairedMachine) {
        connections[machine.id]?.disconnect()
        connections[machine.id] = nil
        MachineStore.remove(id: machine.id)
        OfflineCache.remove(machine.id)
        machines = MachineStore.load()
        if selectedMachineId == machine.id { selectedMachineId = machines.first?.id }
    }

    /// A notification was tapped: switch to that Mac and remember where to go.
    var openChatId: String?
    /// Bumped when a connection's chat list changes, so a pending push open can retry.
    var chatsVersion = 0
    func openFromPush(_ info: PushInfo) {
        if let ws = info.workspaceId, let m = machines.first(where: { connections[$0.id]?.tree.flatMap(\.workspaces).contains { $0.id == ws } ?? false }) {
            selectedMachineId = m.id
        }
        openChatId = info.chatId
    }

    func registerPushToken(_ token: String) {
        pushToken = token
        for c in connections.values where c.state == .connected {
            c.reportPresence(active: true, pushToken: token)
        }
    }
}
