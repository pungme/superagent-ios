import UIKit
import UniformTypeIdentifiers

/// The whole extension: take what was shared, drop it in the inbox, say so,
/// leave. Deciding where it goes happens in the app, with the chat list in
/// front of you — not here in another app's share sheet.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Saving…"
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20)
        ])
        ingest()
    }

    private func ingest() {
        let providers = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { return finish(saved: false) }

        let group = DispatchGroup()
        var texts: [String] = []
        var images: [Data] = []
        let lock = NSLock()

        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                p.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    if let url = item as? URL {
                        lock.lock(); texts.append(url.absoluteString); lock.unlock()
                    }
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    // Whatever arrived — HEIC, PNG, screenshot — leaves as
                    // JPEG, the one format every agent accepts.
                    if let data, let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
                        lock.lock(); images.append(jpeg); lock.unlock()
                    }
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                p.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    if let s = item as? String {
                        lock.lock(); texts.append(s); lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let text = texts.joined(separator: "\n")
            if images.isEmpty {
                if !text.isEmpty { ShareInbox.save(text: text) }
            } else {
                // One item per image so each can be aimed separately; the
                // words ride along with the first.
                for (i, data) in images.enumerated() {
                    ShareInbox.save(text: i == 0 ? text : "", imageData: data)
                }
            }
            self.finish(saved: !text.isEmpty || !images.isEmpty)
        }
    }

    private func finish(saved: Bool) {
        label.text = saved ? "Saved — open Superagent to send" : "Nothing here Superagent can take"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
