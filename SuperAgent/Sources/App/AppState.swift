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

    var selected: PairedMachine? {
        machines.first { $0.id == selectedMachineId } ?? machines.first
    }

    init() {
        selectedMachineId = machines.first?.id
    }

    func connection(for machine: PairedMachine) -> Connection {
        if let c = connections[machine.id] { return c }
        let c = Connection(machine: machine)
        c.onChatsChanged = { [weak self] in self?.chatsVersion += 1 }
        connections[machine.id] = c
        return c
    }

    // MARK: Foreground / background

    func becameActive() {
        for m in machines {
            let c = connection(for: m)
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
        MachineStore.upsert(machine)
        machines = MachineStore.load()
        selectedMachineId = machine.id
        let c = connection(for: machine)
        c.connect()
        c.reportPresence(active: true, pushToken: pushToken)
    }

    func remove(_ machine: PairedMachine) {
        connections[machine.id]?.disconnect()
        connections[machine.id] = nil
        MachineStore.remove(id: machine.id)
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
