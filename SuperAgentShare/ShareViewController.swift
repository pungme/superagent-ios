import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// The whole flow lives here in the sheet: what you shared, your words,
/// which session — and Send delivers over the relay right now, with the
/// app's own connection code. Only when the Mac can't be reached does the
/// item queue, and then the app delivers it silently on its next launch;
/// nobody is asked to "open the app" as a step.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareSheet(
            done: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            providers: (extensionContext?.inputItems ?? [])
                .compactMap { $0 as? NSExtensionItem }
                .flatMap { $0.attachments ?? [] }
        ))
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
    }
}

private struct SharedPayload {
    var text = ""
    var images: [Data] = []
    var isEmpty: Bool { text.isEmpty && images.isEmpty }
}

private struct ShareSheet: View {
    let done: () -> Void
    let providers: [NSItemProvider]

    @State private var payload = SharedPayload()
    @State private var loaded = false
    @State private var note = ""
    @State private var machines = MachineStore.load()
    @State private var snapshot = ShareSnapshot.load()
    @State private var machineId: String?
    @State private var expandedProjects: Set<String> = []
    @State private var sending = false
    @State private var status: String?

    private var machine: PairedMachine? {
        machines.first { $0.id == (machineId ?? machines.first?.id) } ?? machines.first
    }
    private var slice: ShareSnapshot.Machine? {
        snapshot.first { $0.id == machine?.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if machines.isEmpty {
                    unpaired
                } else if let status {
                    Text(status).font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding()
                } else {
                    picker
                }
            }
            .navigationTitle("Send to Superagent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done() } }
            }
        }
        .task { await ingest() }
    }

    /// No Mac paired: the one case where the app genuinely has to come first.
    private var unpaired: some View {
        VStack(spacing: 12) {
            Text("Pair your Mac in Superagent first.").font(.system(size: 16, weight: .medium))
            Button("Keep it for later") {
                stash(destination: nil)
                finish("Saved — it'll be waiting in Superagent")
            }
        }
    }

    private var picker: some View {
        List {
            Section("Shared item") {
                HStack(spacing: 10) {
                    if let data = payload.images.first, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    Text(payload.isEmpty && !loaded ? "Reading…" : (payload.text.isEmpty ? "\(payload.images.count) photo\(payload.images.count == 1 ? "" : "s")" : payload.text))
                        .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Section("Your message") {
                TextField("Add a message (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }
            Section("Text sent to the agent") {
                Text(messageText.isEmpty ? "Photos only — no text" : messageText)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if machines.count > 1 {
                Section {
                    Picker("Mac", selection: Binding(
                        get: { machine?.id ?? "" },
                        set: { machineId = $0 }
                    )) {
                        ForEach(machines) { m in Text(m.name).tag(m.id) }
                    }
                }
            }
            if let slice {
                ForEach(groups(in: slice)) { group in
                    Section(group.name.uppercased()) {
                        ForEach(workspaces(in: group, slice: slice)) { ws in
                            DisclosureGroup(isExpanded: Binding(
                                get: { expandedProjects.contains(ws.id) },
                                set: { if $0 { expandedProjects.insert(ws.id) } else { expandedProjects.remove(ws.id) } }
                            )) {
                                row(label: "New chat", system: "plus.bubble") { send(workspaceId: ws.id, chatId: nil) }
                                ForEach(chats(in: ws)) { chat in
                                    row(label: chat.title ?? "Untitled chat", system: "bubble.left") {
                                        send(workspaceId: ws.id, chatId: chat.id)
                                    }
                                }
                            } label: {
                                Label(ws.name, systemImage: "folder")
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No projects known yet for this Mac — open Superagent once while it's connected.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("Keep it for later") {
                        stash(destination: nil)
                        finish("Saved — it'll be waiting in Superagent")
                    }
                }
            }
        }
        .disabled(sending || !loaded)
        .overlay { if sending { ProgressView() } }
        .onAppear { if let slice { expandedProjects = Set(slice.workspaces.map(\.id)) } }
    }

    private func row(label: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system).font(.system(size: 15)).lineLimit(1)
        }
    }

    private func chats(in ws: ShareSnapshot.Workspace) -> [ShareSnapshot.Chat] {
        (slice?.chats ?? []).filter { $0.workspaceId == ws.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func groups(in slice: ShareSnapshot.Machine) -> [ShareSnapshot.Group] {
        if let groups = slice.groups, !groups.isEmpty { return groups }
        return [.init(id: "projects", name: "Projects")]
    }

    private func workspaces(in group: ShareSnapshot.Group, slice: ShareSnapshot.Machine) -> [ShareSnapshot.Workspace] {
        guard slice.groups?.isEmpty == false else { return slice.workspaces }
        return slice.workspaces.filter { $0.groupId == group.id }
    }

    private var messageText: String {
        let words = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty { return payload.text }
        return payload.text.isEmpty ? words : words + "\n\n" + payload.text
    }

    /// Deliver now over the relay; queue for the app only if the Mac is out
    /// of reach within the extension's patience.
    private func send(workspaceId: String, chatId: String?) {
        guard let machine else { return }
        sending = true
        Task {
            let conn = Connection(machine: machine)
            conn.connect()
            let connected = await conn.waitUntilConnected()
            if connected {
                do {
                    let target: String
                    if let chatId { target = chatId } else {
                        target = try await conn.createChat(workspaceId: workspaceId)
                    }
                    try await conn.sendMessageNow(
                        chatId: target,
                        text: messageText,
                        images: relaySafeImages()
                    )
                    finish("Sent")
                    return
                } catch {
                    // fall through to the queue
                }
            }
            stash(destination: .init(
                id: "", text: "", imageFile: nil, ts: 0,
                machineId: machine.id, workspaceId: workspaceId, chatId: chatId,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            finish("Mac unreachable — queued; it sends automatically")
        }
    }

    private func stash(destination: ShareInbox.Item?) {
        ShareInbox.save(text: payload.text, imageDatas: payload.images, destination: destination)
    }

    private func finish(_ message: String) {
        sending = false
        status = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { done() }
    }

    // MARK: What was shared

    private func ingest() async {
        var texts: [String] = []
        var images: [UIImage] = []
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    texts.append(url.absoluteString)
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // Whatever arrived — HEIC, PNG, screenshot — leaves as JPEG,
                // the one format every agent accepts.
                if let data = await loadData(p, type: UTType.image.identifier),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    texts.append(s)
                }
            }
        }
        let each = 480_000 / max(1, images.count)
        payload = SharedPayload(text: texts.joined(separator: "\n"), images: images.compactMap { compress($0, maxBytes: each) })
        loaded = true
    }

    private func relaySafeImages() -> [(mediaType: String, data: Data)] {
        payload.images.map { (mediaType: "image/jpeg", data: $0) }
    }

    private func compress(_ source: UIImage, maxBytes: Int) -> Data? {
        var image = resized(source, maxSide: 1600)
        var quality: CGFloat = 0.82
        var data = image.jpegData(compressionQuality: quality) ?? Data()
        while data.count > maxBytes, max(image.size.width, image.size.height) >= 200 {
            if quality > 0.5 { quality -= 0.12 }
            else { image = resized(image, maxSide: max(image.size.width, image.size.height) * 0.75); quality = 0.7 }
            data = image.jpegData(compressionQuality: quality) ?? Data()
        }
        return data
    }

    private func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private func loadData(_ p: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { cont in
            p.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                cont.resume(returning: data)
            }
        }
    }
}
