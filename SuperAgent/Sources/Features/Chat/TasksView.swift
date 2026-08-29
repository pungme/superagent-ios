import SwiftUI

/// The agent's plan for this conversation, read off its planning tool calls:
/// the latest TodoWrite list, plus TaskCreate items with their TaskUpdate
/// statuses (the id comes back in the create call's result).
struct TaskItem: Identifiable, Hashable {
    let id: String
    let text: String
    let status: String
    var isDone: Bool { status == "completed" || status == "done" }
    var isActive: Bool { status == "in_progress" }
}

enum TaskList {
    static func build(_ events: [WireEvent]) -> [TaskItem] {
        var todos: [TaskItem] = []
        var created: [(toolId: String, subject: String)] = []
        var idByTool: [String: String] = [:]
        var status: [String: String] = [:]
        for e in events {
            switch e.data {
            case let .tool(toolId, name, _, task):
                guard let task else { continue }
                if name == "TodoWrite", let list = task.todos {
                    todos = list.enumerated().map { TaskItem(id: "todo-\($0.offset)", text: $0.element.text, status: $0.element.status) }
                } else if name == "TaskCreate", let s = task.subject {
                    created.append((toolId, s))
                } else if name == "TaskUpdate", let id = task.taskId, let st = task.status {
                    status[id] = st
                }
            case let .toolResult(toolId, _, summary):
                if created.contains(where: { $0.toolId == toolId }), let m = summary.firstMatch(of: /#(\d+)/) {
                    idByTool[toolId] = String(m.1)
                }
            default: break
            }
        }
        let tasks = created.map { c in
            let id = idByTool[c.toolId]
            return TaskItem(id: "task-\(c.toolId)", text: c.subject, status: id.flatMap { status[$0] } ?? "pending")
        }
        return todos + tasks
    }
}

struct TasksView: View {
    let tasks: [TaskItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if tasks.isEmpty {
                    ContentUnavailableView("No plan yet", systemImage: "checklist",
                                           description: Text("When the agent writes a to-do list it shows up here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(tasks) { t in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: t.isDone ? "checkmark.circle.fill" : (t.isActive ? "circle.dotted.circle" : "circle"))
                            .foregroundStyle(t.isDone ? Theme.working : (t.isActive ? Theme.needsYou : Theme.textTertiary))
                            .padding(.top, 1)
                        Text(t.text)
                            .foregroundStyle(t.isDone ? Theme.textTertiary : Theme.textPrimary)
                            .strikethrough(t.isDone, color: Theme.textTertiary)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle(tasks.isEmpty ? "Tasks" : "Tasks · \(tasks.filter(\.isDone).count)/\(tasks.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
