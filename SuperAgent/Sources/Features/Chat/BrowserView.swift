import SwiftUI

/// The Mac's browser pane for this conversation, mirrored: a fresh capture
/// every couple of seconds while this is open, a URL bar that opens pages on
/// the Mac, and a way to hand the current view to the agent as a picture.
struct BrowserView: View {
    let connection: Connection
    let chat: WireChat
    var onAttach: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shot: WireBrowserShot?
    @State private var image: UIImage?
    @State private var unavailable: String?
    @State private var url = ""
    @State private var opening = false
    @State private var error: String?
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundStyle(Theme.textTertiary)
                    TextField("Open a page on the Mac…", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($urlFocused)
                        .onSubmit(open)
                    if opening { ProgressView().controlSize(.small) }
                    else if !url.isEmpty {
                        Button(action: open) { Image(systemName: "arrow.right.circle.fill").font(.system(size: 20)) }
                            .tint(Theme.textPrimary)
                            .accessibilityLabel("Open")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
                .padding(.horizontal, 12).padding(.vertical, 8)

                Group {
                    if let image {
                        ScrollView {
                            Image(uiImage: image)
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
                                .padding(.horizontal, 12)
                        }
                    } else if let unavailable {
                        ContentUnavailableView("Nothing to show yet", systemImage: "safari",
                                               description: Text(unavailable + "\nType an address above and it opens on the Mac."))
                    } else {
                        ProgressView("Looking at the Mac's browser…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let shot {
                    VStack(spacing: 6) {
                        Text(shot.title.isEmpty ? shot.url : shot.title)
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        HStack(spacing: 22) {
                            Button { nav("back") } label: { Image(systemName: "chevron.left") }.disabled(!shot.canGoBack)
                            Button { nav("forward") } label: { Image(systemName: "chevron.right") }.disabled(!shot.canGoForward)
                            Button { nav("reload") } label: { Image(systemName: "arrow.clockwise") }
                            Spacer()
                            Button {
                                if let d = image?.jpegData(compressionQuality: 0.8) { onAttach(d); Haptics.tap(); dismiss() }
                            } label: { Label("Send to agent", systemImage: "paperclip") }
                                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentFg)
                        }
                        .font(.system(size: 17, weight: .medium))
                        .tint(Theme.textPrimary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.panel)
                }
            }
            .background(Theme.panel)
            .navigationTitle("Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await poll() }
            .alert("Browser", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refresh() async {
        do {
            let s = try await connection.browserShot(chatId: chat.id)
            shot = s
            unavailable = nil
            if let d = Data(base64Encoded: s.jpeg), let img = UIImage(data: d) { image = img }
            if !urlFocused, url.isEmpty || url == shot?.url { url = s.url }
        } catch let e as RpcError where e.code == "unavailable" {
            if shot == nil { unavailable = e.message; image = nil }
        } catch {
            if shot == nil { unavailable = error.localizedDescription }
        }
    }

    private func open() {
        let target = url.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !opening else { return }
        opening = true
        urlFocused = false
        Task {
            defer { opening = false }
            do {
                url = try await connection.browserOpen(chatId: chat.id, url: target)
                Haptics.tap()
                await refresh()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func nav(_ action: String) {
        Task {
            do { try await connection.browserNav(chatId: chat.id, action: action); try? await Task.sleep(for: .milliseconds(600)); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
}
