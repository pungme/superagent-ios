import SwiftUI

/// One picture in a conversation, named by where it comes from, so the viewer
/// can fetch the ones around the one you tapped.
enum ChatImageSource: Hashable, Sendable {
    /// A picture sent with a message, or a tool's own (keyed by that id).
    case sent(messageId: String, index: Int)
    /// An image in a reply's markdown: its address as written.
    case markdown(String)
    /// An image the agent handed over.
    case file(workspaceId: String, path: String, chatId: String)
}

/// Every picture in the conversation, in order, and what it takes to load one
/// that has not been scrolled to. The full-screen viewer swipes through these.
struct ChatGallery {
    let connection: Connection
    let sources: [ChatImageSource]
    let markdownLoader: (@Sendable (String) async -> Data?)?

    static func sources(in events: [WireEvent]) -> [ChatImageSource] {
        var out: [ChatImageSource] = []
        for event in events {
            switch event.data {
            case let .user(id, _, images, _, _):
                for i in images.indices { out.append(.sent(messageId: id, index: i)) }
            case let .toolResult(toolId, _, _, images):
                for i in images.indices { out.append(.sent(messageId: toolId, index: i)) }
            case let .assistant(_, text):
                out += markdownImages(in: text).map(ChatImageSource.markdown)
            case let .file(_, path, _, workspaceId, _, mediaType):
                guard let workspaceId, isImage(path: path, mediaType: mediaType) else { continue }
                out.append(.file(workspaceId: workspaceId, path: path, chatId: event.chatId))
            default: break
            }
        }
        return out
    }

    static func isImage(path: String, mediaType: String?) -> Bool {
        if let mediaType { return mediaType.hasPrefix("image/") }
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"].contains(ext)
    }

    private static let markdownImage = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(\s*<?([^)>\s]+)>?[^)]*\)"#)

    static func markdownImages(in text: String) -> [String] {
        let ns = text as NSString
        return markdownImage.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    /// A file a reply points at, as the reply's own image view fetches it.
    @MainActor
    static func fetchMarkdownFile(_ connection: Connection, chatId: String, path: String) async -> Data? {
        guard let ws = connection.chats.first(where: { $0.id == chatId })?.workspaceId,
              case let .image(_, _, _, b64)? = try? await connection.readFile(workspaceId: ws, path: path, chatId: chatId)
        else { return nil }
        return Data(base64Encoded: b64)
    }

    /// The picture itself, fetched the way the row that shows it would.
    func load(_ source: ChatImageSource) async -> UIImage? {
        switch source {
        case let .sent(messageId, index):
            guard let wire = try? await connection.chatImage(messageId: messageId, index: index),
                  let data = Data(base64Encoded: wire.data) else { return nil }
            return UIImage(data: data)
        case let .markdown(src):
            var data: Data?
            if let url = URL(string: src), url.scheme == "https" || url.scheme == "http" {
                data = try? await URLSession.shared.data(from: url).0
            } else if let markdownLoader {
                let path = src.hasPrefix("file://") ? (URL(string: src)?.path ?? src) : src
                data = await markdownLoader(path)
            }
            return data.flatMap(UIImage.init(data:))
        case let .file(workspaceId, path, chatId):
            let key = "\(workspaceId)|\(chatId)|\(path)"
            if let hit = await MainActor.run(body: { FileImageCache.images[key] }) { return hit }
            guard case let .image(_, _, _, b64)? = try? await connection.readFile(
                      workspaceId: workspaceId, path: path, chatId: chatId),
                  let data = Data(base64Encoded: b64),
                  let ui = UIImage(data: data) else { return nil }
            await MainActor.run { FileImageCache.images[key] = ui }
            return ui
        }
    }
}

extension EnvironmentValues {
    @Entry var chatGallery: ChatGallery? = nil
    /// The markdown loader a reply uses, for the gallery to reach the same files.
}
