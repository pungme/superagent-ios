import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onPair: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Paired Macs") {
                    ForEach(app.machines) { m in
                        let c = app.connections[m.id]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                Text(c?.state == .connected ? "Connected" : "Not connected · \(m.relay)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if app.selectedMachineId == m.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { app.selectedMachineId = m.id }
                        .swipeActions {
                            Button(role: .destructive) { app.remove(m) } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    Button { onPair() } label: { Label("Pair another Mac", systemImage: "plus") }
                }
                // What today has cost on the relay. It has a daily ceiling per Mac,
                // and when it runs out everything simply stops reaching the Mac —
                // worth being able to watch rather than meet as an outage.
                if let usage = app.connections[app.selectedMachineId ?? ""]?.relayUsage {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Data used")
                                Spacer()
                                Text(usage.summary).foregroundStyle(.secondary)
                            }
                            ProgressView(value: usage.fraction)
                                .tint(usage.fraction > 0.8 ? Theme.danger : Theme.accent)
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text("Relay")
                    } footer: {
                        Text("Resets at midnight UTC. Mirroring a page or the simulator is what spends it; everything else is tiny.")
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                    LabeledContent("Device id", value: String(DeviceIdentity.id.prefix(8)))
                } footer: {
                    Text("Everything between this phone and your Mac is end-to-end encrypted; the relay only forwards. Remove a Mac here or from the Mac's Settings → Phone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
