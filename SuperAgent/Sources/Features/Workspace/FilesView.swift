import PDFKit
import SwiftUI
import UIKit

/// A file inside a project, for navigation.
struct FileRef: Hashable {
    let workspaceId: String
    let path: String
    /// The conversation it came from, when it came from one. A chat on its own
    /// worktree keeps its files there, so reading them needs the chat, not just
    /// the project.
    var chatId: String?
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
                .superFont(13)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            Text(name).superFont(13.5).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
            Spacer()
            if isDir { Image(systemName: "chevron.right").superFont(12, weight: .semibold).foregroundStyle(Theme.textTertiary) }
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
    /// The whole file, fetched for the share sheet: Save to Files, Save Image,
    /// AirDrop, another app. Nil until Save is tapped.
    @State private var saving: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case fetching(done: Int, of: Int)
        case ready(URL)
        case failed(String)
    }

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
                                        .superFont(12.5, design: .monospaced)
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
                        ZoomableImage(image: img)
                    } else {
                        ContentUnavailableView("Couldn't decode the picture", systemImage: "photo")
                    }
                case let .pdf(_, size, chunks):
                    PDFFileView(connection: connection, ref: ref, size: size, chunks: chunks)
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = ref.path; Haptics.tap() } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy path")
                if case let .fetching(done, of) = saving {
                    ProgressView(value: Double(done), total: Double(max(of, 1)))
                        .progressViewStyle(.circular)
                        .accessibilityLabel("Getting the file")
                } else {
                    Button { Task { await save() } } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Save or share")
                        .accessibilityIdentifier("save-file")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { if case .ready = saving { return true } else { return false } },
            set: { if !$0 { saving = .idle } }
        )) {
            if case let .ready(url) = saving { ShareSheet(items: [url]) }
        }
        .alert("Couldn't get the file", isPresented: Binding(
            get: { if case .failed = saving { return true } else { return false } },
            set: { if !$0 { saving = .idle } }
        )) {
            Button("OK") {}
        } message: {
            if case let .failed(why) = saving { Text(why) }
        }
        .task {
            do { content = try await connection.readFile(workspaceId: ref.workspaceId, path: ref.path, chatId: ref.chatId) }
            catch { self.error = error.localizedDescription }
        }
    }
}

extension FileView {
    /// The file's own bytes, in the relay-sized slices the Mac already serves
    /// PDFs in (any file up to its 25 MB cap), written to a temporary file under
    /// the file's own name so the share sheet saves it as itself.
    fileprivate func save() async {
        Haptics.tap()
        saving = .fetching(done: 0, of: 1)
        var bytes = Data()
        var total = 1
        var index = 0
        do {
            while index < total {
                let slice = try await connection.readFileChunk(workspaceId: ref.workspaceId, path: ref.path,
                                                               index: index, chatId: ref.chatId)
                guard let d = Data(base64Encoded: slice.data) else {
                    saving = .failed("A slice of the file didn't decode.")
                    return
                }
                bytes.append(d)
                total = max(slice.chunks, 1)
                index += 1
                saving = .fetching(done: index, of: total)
            }
        } catch let e as RpcError {
            saving = .failed(e.code == "not-found"
                ? "The Mac couldn't send it. Files larger than 25 MB stay on the Mac."
                : e.message)
            return
        } catch let e {
            saving = .failed(e.localizedDescription)
            return
        }
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent((ref.path as NSString).lastPathComponent)
            try bytes.write(to: url)
            saving = .ready(url)
        } catch {
            saving = .failed(error.localizedDescription)
        }
    }
}

/// The system share sheet: Save to Files, Save Image, AirDrop, Mail, other apps.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Title + project name in the bar, as the desktop's header names the project.
struct PanelTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 1) {
            Text(title).superFont(15, weight: .semibold).lineLimit(1)
            Text(subtitle).superFont(11).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }
}

/// A PDF, pulled over in slices and rendered by PDFKit so the text stays
/// selectable and searchable rather than becoming pictures of pages.
private struct PDFFileView: View {
    let connection: Connection
    let ref: FileRef
    let size: Int
    let chunks: Int

    @State private var document: PDFDocument?
    @State private var loaded = 0
    @State private var error: String?

    var body: some View {
        Group {
            if let document {
                PDFKitView(document: document)
            } else if let error {
                ContentUnavailableView("Couldn\'t open the PDF", systemImage: "doc.richtext",
                                       description: Text(error))
            } else {
                VStack(spacing: 10) {
                    ProgressView(value: Double(loaded), total: Double(max(chunks, 1)))
                        .frame(maxWidth: 220)
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ref.path) { await load() }
    }

    private func load() async {
        guard document == nil, chunks > 0 else { return }
        var bytes = Data()
        bytes.reserveCapacity(size)
        for i in 0..<chunks {
            do {
                let slice = try await connection.readFileChunk(workspaceId: ref.workspaceId, path: ref.path, index: i, chatId: ref.chatId)
                guard let d = Data(base64Encoded: slice.data) else {
                    error = "That slice of the file didn\'t decode."
                    return
                }
                bytes.append(d)
                loaded = i + 1
            } catch let e as RpcError {
                error = e.message
                return
            } catch let e {
                error = e.localizedDescription
                return
            }
        }
        guard let doc = PDFDocument(data: bytes) else {
            error = "The file arrived but PDFKit wouldn\'t open it."
            return
        }
        document = doc
    }
}

/// PDFKit\'s own view: paging, pinch to zoom, selection and Find all come with it.
private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.document = document
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
    }
}
