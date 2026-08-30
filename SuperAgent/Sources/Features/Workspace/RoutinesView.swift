import SwiftUI

/// The project's routines: what runs on a schedule, when it last ran, and a
/// switch. "Run now" starts one on the Mac immediately.
struct RoutinesView: View {
    let connection: Connection
    let workspace: WireWorkspace
    @State private var routines: [WireRoutine] = []
    @State private var loading = true
    @State private var selected: WireRoutine?
    @State private var error: String?

    private var mine: [WireRoutine] { routines.filter { $0.workspaceId == workspace.id } }

    var body: some View {
        List {
            if loading {
                HStack { ProgressView(); Text("Loading routines…").foregroundStyle(.secondary) }.listRowBackground(Theme.card)
            } else if mine.isEmpty {
                ContentUnavailableView("No routines", systemImage: "clock.arrow.2.circlepath",
                                       description: Text("Ask the agent on the Mac to set one up: “every morning, check the build”."))
                    .listRowBackground(Color.clear)
            }
            ForEach(mine) { r in
                RoutineRow(routine: r,
                           toggle: { on in setEnabled(r, on) },
                           runNow: { run(r) },
                           open: { selected = r })
                    .listRowBackground(Theme.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { PanelTitle(title: "Routines", subtitle: workspace.name) } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { r in RoutineSheet(routine: r) }
        .alert("Routines", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func load() async {
        do { routines = try await connection.listRoutines() } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func setEnabled(_ r: WireRoutine, _ on: Bool) {
        routines = routines.map { var x = $0; if x.id == r.id { x.enabled = on ? 1 : 0 }; return x }
        Task {
            do { try await connection.setRoutineEnabled(id: r.id, enabled: on); Haptics.tap() }
            catch { self.error = error.localizedDescription; await load() }
        }
    }

    private func run(_ r: WireRoutine) {
        routines = routines.map { var x = $0; if x.id == r.id { x.lastRunStatus = "running" }; return x }
        Task {
            do { try await connection.runRoutineNow(id: r.id); Haptics.success() }
            catch { self.error = error.localizedDescription }
            try? await Task.sleep(for: .seconds(3))
            await load()
        }
    }
}

private struct RoutineRow: View {
    let routine: WireRoutine
    let toggle: (Bool) -> Void
    let runNow: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button(action: open) {
                    Text(routine.prompt).superFont(15).foregroundStyle(Theme.textPrimary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Spacer()
                Toggle("Enabled", isOn: Binding(get: { routine.isEnabled }, set: { toggle($0) })).labelsHidden().tint(Theme.working)
            }
            HStack(spacing: 6) {
                Image(systemName: statusIcon).foregroundStyle(statusColor)
                Text(summary).superFont(12).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                Button(action: runNow) {
                    Label("Run now", systemImage: "play.fill").superFont(12, weight: .semibold)
                }
                .buttonStyle(.bordered).controlSize(.small).tint(Theme.textPrimary)
                .disabled(routine.lastRunStatus == "running")
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch routine.lastRunStatus {
        case "ok": "checkmark.circle.fill"
        case "error": "xmark.circle.fill"
        case "running": "circle.dotted"
        default: "clock"
        }
    }
    private var statusColor: Color {
        switch routine.lastRunStatus {
        case "ok": Theme.working
        case "error": Theme.danger
        case "running": Theme.needsYou
        default: Theme.textTertiary
        }
    }
    private var summary: String {
        var parts = ["every \(interval)"]
        if routine.lastRunStatus == "running" { parts.append("running now") }
        else if let at = routine.lastRunAt {
            parts.append("last \(Date(timeIntervalSince1970: at / 1000).formatted(.relative(presentation: .named)))")
        } else { parts.append("never run") }
        if let n = routine.runCount, n > 0 { parts.append("\(n) run\(n == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
    private var interval: String {
        let h = routine.intervalMs / 3_600_000
        if h >= 24, h.truncatingRemainder(dividingBy: 24) == 0 { let d = Int(h / 24); return d == 1 ? "day" : "\(d) days" }
        return h == 1 ? "hour" : "\(Int(h)) hours"
    }
}

private struct RoutineSheet: View {
    let routine: WireRoutine
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Prompt") { Text(routine.prompt).textSelection(.enabled) }
                Section("Last run") {
                    if let s = routine.lastRunSummary, !s.isEmpty { Text(s).textSelection(.enabled) }
                    else { Text("Nothing recorded yet").foregroundStyle(.secondary) }
                    if let at = routine.lastRunAt {
                        LabeledContent("When", value: Date(timeIntervalSince1970: at / 1000).formatted(date: .abbreviated, time: .shortened))
                    }
                    if let t = routine.lastRunTokens, t > 0 { LabeledContent("Tokens", value: t.formatted(.number.notation(.compactName))) }
                }
                Section {
                    LabeledContent("Next run", value: routine.isEnabled ? Date(timeIntervalSince1970: routine.nextRunAt / 1000).formatted(.relative(presentation: .named)) : "Paused")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
