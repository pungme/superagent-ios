import SwiftUI

/// The project's board, one column at a time. Tap a card to read or move it;
/// the Mac's board redraws as you do.
struct BoardView: View {
    let connection: Connection
    let workspace: WireWorkspace
    @State private var cards: [WireCard] = []
    @State private var loading = true
    @State private var column: CardStatus = .todo
    @State private var selected: WireCard?
    @State private var adding = false
    @State private var error: String?

    private var shown: [WireCard] { cards.filter { $0.status == column }.sorted { $0.position < $1.position } }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Column", selection: $column) {
                ForEach(CardStatus.allCases, id: \.self) { s in
                    let n = cards.filter { $0.status == s }.count
                    Text(n > 0 ? "\(s.label) \(n)" : s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.bottom, 6)
            List {
                if loading {
                    HStack { ProgressView(); Text("Loading the board…").foregroundStyle(.secondary) }.listRowBackground(Theme.card)
                } else if shown.isEmpty {
                    Text("Nothing in \(column.label)").foregroundStyle(.secondary).listRowBackground(Theme.card)
                }
                ForEach(shown) { card in
                    Button { selected = card } label: { CardRow(card: card) }
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let next = next(after: card.status) {
                                Button { move(card, to: next) } label: { Label(next.label, systemImage: "arrow.right") }.tint(Theme.working)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if let prev = previous(before: card.status) {
                                Button { move(card, to: prev) } label: { Label(prev.label, systemImage: "arrow.left") }.tint(Theme.textSecondary)
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.panel)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .disabled(connection.state != .connected)
                    .accessibilityLabel("New card")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { card in
            CardSheet(card: card, onMove: { move(card, to: $0) }, onSave: { title, body in save(card, title: title, body: body) })
        }
        .sheet(isPresented: $adding) {
            NewCardSheet(column: column) { title, body in
                Task {
                    do { _ = try await connection.addCard(workspaceId: workspace.id, title: title, body: body, status: column); Haptics.tap(); await load() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .alert("Board", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func next(after s: CardStatus) -> CardStatus? {
        let all = CardStatus.allCases
        guard let i = all.firstIndex(of: s), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
    private func previous(before s: CardStatus) -> CardStatus? {
        let all = CardStatus.allCases
        guard let i = all.firstIndex(of: s), i > 0 else { return nil }
        return all[i - 1]
    }

    private func load() async {
        do { cards = try await connection.listCards(workspaceId: workspace.id) } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func move(_ card: WireCard, to status: CardStatus) {
        // Optimistic: the row jumps columns now; the Mac's answer confirms it.
        cards = cards.map { var c = $0; if c.id == card.id { c.status = status }; return c }
        Task {
            do { let updated = try await connection.moveCard(id: card.id, to: status); cards = cards.map { $0.id == updated.id ? updated : $0 }; Haptics.tap() }
            catch { self.error = error.localizedDescription; await load() }
        }
    }

    private func save(_ card: WireCard, title: String, body: String) {
        Task {
            do { let updated = try await connection.updateCard(id: card.id, title: title, body: body); cards = cards.map { $0.id == updated.id ? updated : $0 } }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct CardRow: View {
    let card: WireCard
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(2)
            if !card.body.isEmpty {
                Text(card.body).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            if !card.tags.isEmpty || card.branch != nil || !card.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.tags, id: \.self) { t in
                        Text(t).font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.textSecondary)
                    }
                    if let b = card.branch, !b.isEmpty { BranchChip(branch: b) }
                    if !card.images.isEmpty { Label("\(card.images.count)", systemImage: "photo").font(.system(size: 11)).foregroundStyle(Theme.textTertiary) }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Read a card, edit its words, or send it to another column.
private struct CardSheet: View {
    let card: WireCard
    let onMove: (CardStatus) -> Void
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var body_: String

    init(card: WireCard, onMove: @escaping (CardStatus) -> Void, onSave: @escaping (String, String) -> Void) {
        self.card = card; self.onMove = onMove; self.onSave = onSave
        _title = State(initialValue: card.title)
        _body_ = State(initialValue: card.body)
    }

    private var dirty: Bool { title != card.title || body_ != card.body }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Details", text: $body_, axis: .vertical).lineLimit(3...12)
                }
                Section("Column") {
                    Picker("Column", selection: Binding(get: { card.status }, set: { onMove($0); dismiss() })) {
                        ForEach(CardStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if !card.tags.isEmpty {
                    Section("Tags") { Text(card.tags.joined(separator: " · ")).foregroundStyle(.secondary) }
                }
                Section {
                    LabeledContent("Updated", value: Date(timeIntervalSince1970: card.updatedAt / 1000).formatted(date: .abbreviated, time: .shortened))
                    if let b = card.branch, !b.isEmpty { LabeledContent("Branch", value: b) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(title.trimmingCharacters(in: .whitespaces), body_); dismiss() }
                        .disabled(!dirty || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct NewCardSheet: View {
    let column: CardStatus
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs doing?", text: $title).focused($focused)
                TextField("Details (optional)", text: $body_, axis: .vertical).lineLimit(3...10)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle("New card in \(column.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(title.trimmingCharacters(in: .whitespaces), body_); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
