import SwiftUI

/// A file inside a project, for navigation.
struct FileRef: Hashable {
    let workspaceId: String
    let path: String
}

/// A folder inside a project. Opening one pushes its own screen — the phone
/// idiom — rather than swapping the list under you.
struct FolderRef: Hashable {
    let workspaceId: String
    /// Path with a trailing slash, as `files.list` reports it; "" is the project root.
    let dir: String
    /// The listing, carried down so a folder doesn't ask the Mac again.
    let files: [String]

    var name: String {
        dir.isEmpty ? "Files" : String(dir.dropLast().split(separator: "/").last ?? "")
    }
}

/// One folder of a project: its sub-folders, then its files, with a filter that
/// searches everything below it. Read-only: you look, the agent edits.
struct FilesView: View {
    let connection: Connection
    let workspace: WireWorkspace
    /// Nil at the project root — the root loads the listing and hands it down.
    var folder: FolderRef?

    @State private var loaded: [String] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter = ""

    private var dir: String { folder?.dir ?? "" }
    private var files: [String] { folder?.files ?? loaded }
    private var isRoot: Bool { folder == nil }

    private struct Entry: Identifiable {
        let path: String
        let name: String
        let isDir: Bool
        var id: String { path }
    }

    private var entries: [Entry] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            // Searching looks through everything under this folder, files only.
            return files
                .filter { $0.hasPrefix(dir) && !$0.hasSuffix("/") && $0.dropFirst(dir.count).lowercased().contains(q) }
                .prefix(200)
                .map { Entry(path: $0, name: String($0.dropFirst(dir.count)), isDir: false) }
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
            if loading, isRoot {
                HStack { ProgressView(); Text("Listing files…").foregroundStyle(.secondary) }.listRowBackground(Theme.card)
            } else if entries.isEmpty {
                Text(filter.isEmpty ? "Empty folder" : "Nothing matches").foregroundStyle(.secondary).listRowBackground(Theme.card)
            }
            ForEach(entries) { e in
                if e.isDir {
                    NavigationLink(value: FolderRef(workspaceId: workspace.id, dir: e.path, files: files)) {
                        FileRow(name: e.name, isDir: true)
                    }
                    .listRowBackground(Theme.card)
                } else {
                    NavigationLink(value: FileRef(workspaceId: workspace.id, path: e.path)) {
                        FileRow(name: e.name, isDir: false)
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: isRoot ? "Filter files" : "Filter in \(folder?.name ?? "")")
        .navigationTitle(folder?.name ?? "Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                PanelTitle(title: folder?.name ?? "Files", subtitle: parentLabel)
            }
        }
        .task { if isRoot { await load() } }
        .refreshable { if isRoot { await load() } }
        .alert("Couldn't list files", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    /// Where this folder sits: the project, then the folders above this one.
    private var parentLabel: String {
        let parents = dir.dropLast().split(separator: "/").dropLast()
        return ([workspace.name] + parents.map(String.init)).joined(separator: " / ")
    }

    private func load() async {
        do { loaded = try await connection.listFiles(workspaceId: workspace.id).files } catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct FileRow: View {
    let name: String
    let isDir: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDir ? "folder" : icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            Text(name).font(.system(size: 13.5)).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
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

    private var isMarkdown: Bool { ["md", "markdown"].contains((ref.path as NSString).pathExtension.lowercased()) }

    var body: some View {
        Group {
            if let content {
                switch content {
                case let .text(_, _, text, truncated):
                    // Markdown renders formatted, like the desktop viewer's View mode;
                    // everything else is monospace with two-axis scroll, pinned top-left
                    // (a two-axis ScrollView centres content smaller than itself).
                    GeometryReader { geo in
                        ScrollView(isMarkdown ? [.vertical] : [.vertical, .horizontal]) {
                            VStack(alignment: .leading, spacing: 0) {
                                if isMarkdown {
                                    MarkdownView(text: text).padding(14)
                                } else {
                                    Text(text)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)
                                        .textSelection(.enabled)
                                        .padding(14)
                                }
                                if truncated {
                                    Text("Showing the first part of a large file.")
                                        .font(.footnote).foregroundStyle(Theme.textTertiary).padding(14)
                                }
                            }
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// Title + project name in the bar, as the desktop's header names the project.
struct PanelTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }
}
