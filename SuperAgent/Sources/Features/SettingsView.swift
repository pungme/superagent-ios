import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accent") private var accentChoice = ""

    var onPair: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    // The same seven as the desktop, so one product, one pink.
                    // Picking a colour also swaps the home-screen icon to match:
                    // on iOS the icon is the one place the app shows its colour
                    // when closed, and a bundled alternate icon changes it for
                    // real — unlike the Mac, where only the running Dock icon can.
                    HStack(spacing: 12) {
                        ForEach(Theme.Accent.allCases, id: \.rawValue) { a in
                            Button {
                                UserDefaults.standard.set(a.rawValue, forKey: "accent")
                                accentChoice = a.rawValue
                                UIApplication.shared.setAlternateIconName(a.iconName)
                            } label: {
                                Circle()
                                    .fill(a.colour.map(Color.init) ?? Theme.textPrimary)
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        if accentChoice == a.rawValue || (accentChoice.isEmpty && a == .standard) {
                                            Circle().strokeBorder(Theme.textPrimary, lineWidth: 2).padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(a == .standard ? "Default accent" : "\(a.rawValue) accent")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)

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
