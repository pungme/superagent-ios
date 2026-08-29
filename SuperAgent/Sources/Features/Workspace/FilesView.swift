import SwiftUI

/// A file inside a project, for navigation.
struct FileRef: Hashable {
    let workspaceId: String
    let path: String
}

/// The project's files, one folder at a time, with a filter that searches
/// every level. Read-only: you look, the agent edits.
struct FilesView: View {
    let connection: Connection
    let workspace: WireWorkspace
    @State private var files: [String] = []
    @State private var loading = true
    @State private var error: String?
    @State private var dir = ""
    @State private var filter = ""

    private struct Entry: Identifiable {
        let path: String
        let name: String
        let isDir: Bool
        var id: String { path }
    }

    private var entries: [Entry] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            return files.filter { !$0.hasSuffix("/") && $0.lowercased().contains(q) }
                .prefix(200)
                .map { Entry(path: $0, name: $0, isDir: false) }
        }
        var out: [Entry] = []
        for f in files where f.hasPrefix(dir) {
            let rest = f.dropFirst(dir.count)
            guard !rest.isEmpty else { continue }
            if rest.hasSuffix("/") {
                if rest.dropLast().contains("/") { continue }
                out.append(Entry(path: f, name: String(rest.dropLast()), isDir: true))
            } else if !rest.contains("/") {
                out.append(Entry(path: f, name: String(rest), isDir: false))
            }
        }
        return out.sorted { a, b in a.isDir != b.isDir ? a.isDir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    var body: some View {
        List {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                TextField("Filter files", text: $filter)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !filter.isEmpty {
                    Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary) }
                        .accessibilityLabel("Clear filter")
                }
            }
            .listRowBackground(Theme.card)
            if !dir.isEmpty, filter.isEmpty {
                Button {
                    let parts = dir.dropLast().split(separator: "/")
                    dir = parts.dropLast().map { $0 + "/" }.joined()
                } label: {
                    Label(String(dir.dropLast()), systemImage: "chevron.left").foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                .listRowBackground(Theme.card)
            }
            if loading {
                HStack { ProgressView(); Text("Listing files…").foregroundStyle(.secondary) }.listRowBackground(Theme.card)
            } else if entries.isEmpty {
                Text(filter.isEmpty ? "Empty folder" : "Nothing matches").foregroundStyle(.secondary).listRowBackground(Theme.card)
            }
            ForEach(entries) { e in
                if e.isDir {
                    Button { dir = e.path } label: { FileRow(name: e.name, isDir: true) }
                        .listRowBackground(Theme.card)
                } else {
                    NavigationLink(value: FileRef(workspaceId: workspace.id, path: e.path)) {
                        FileRow(name: e.name, isDir: false)
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .task { await load() }
        .refreshable { await load() }
        .alert("Couldn't list files", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func load() async {
        do { files = try await connection.listFiles(workspaceId: workspace.id).files } catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct FileRow: View {
    let name: String
    let isDir: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDir ? "folder.fill" : icon)
                .foregroundStyle(isDir ? Theme.needsYou : Theme.textSecondary)
                .frame(width: 20)
            Text(name).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
            Spacer()
            if isDir { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary) }
        }
    }
    private var icon: String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": "photo"
        case "md", "txt", "rtf": "doc.text"
        case "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "m", "sh", "css", "html", "json", "yml", "yaml", "toml": "chevron.left.forwardslash.chevron.right"
        case "pdf": "doc.richtext"
        default: "doc"
        }
    }
}

/// One file: text in monospace (both-axis scroll), pictures as pictures.
struct FileView: View {
    let connection: Connection
    let ref: FileRef
    @State private var content: WireFileContent?
    @State private var error: String?

    var body: some View {
        Group {
            if let content {
                switch content {
                case let .text(_, _, text, truncated):
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(text)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                                .padding(14)
                            if truncated {
                                Text("Showing the first part of a large file.")
                                    .font(.footnote).foregroundStyle(Theme.textTertiary).padding(14)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case let .image(_, _, _, data):
                    if let d = Data(base64Encoded: data), let img = UIImage(data: d) {
                        ScrollView { Image(uiImage: img).resizable().scaledToFit().padding(14) }
                    } else {
                        ContentUnavailableView("Couldn't decode the picture", systemImage: "photo")
                    }
                case let .binary(_, size):
                    ContentUnavailableView("No preview", systemImage: "doc.zipper",
                                           description: Text("\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) · not text or a picture"))
                }
            } else if let error {
                ContentUnavailableView("Couldn't open it", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
        .navigationTitle((ref.path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = ref.path; Haptics.tap() } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy path")
            }
        }
        .task {
            do { content = try await connection.readFile(workspaceId: ref.workspaceId, path: ref.path) }
            catch { self.error = error.localizedDescription }
        }
    }
}
