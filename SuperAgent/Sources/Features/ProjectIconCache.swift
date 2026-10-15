import CryptoKit
import Foundation
import Observation
import UIKit

/// Project icons, kept.
///
/// Every row used to ask the Mac for its project's icon each time it appeared,
/// over the relay, and keep nothing: a list scrolled, a sidebar redrawn or a
/// chat switched showed folders until the answers came back — slowly on a
/// slow link, and not at all when one timed out. Icons almost never change.
///
/// So they are kept: in memory for the rows on screen, on disk so the next
/// launch has them at once, and fetched at most once per project at a time.
/// A fetch that fails leaves what was there; an answer that arrives replaces
/// it. Asked again only after a while, quietly, behind the icon already shown.
@MainActor
@Observable
final class ProjectIconCache {
    static let shared = ProjectIconCache()

    enum Icon: Equatable {
        case image(UIImage)
        case kind(String)
    }

    /// What rows draw from. Observed, so a row redraws when its icon lands.
    private(set) var icons: [String: Icon] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inflight: Set<String> = []
    @ObservationIgnored private var checkedDisk: Set<String> = []

    /// How long a fetched icon is trusted before it is asked for again.
    static let freshFor: TimeInterval = 10 * 60

    private let dir: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let d = caches.appendingPathComponent("project-icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func key(machine: String, workspace: WireWorkspace) -> String {
        "\(machine)|\(workspace.id)|\(workspace.path)"
    }

    /// The icon to draw now: from memory, else from disk. Never waits on the Mac.
    func icon(for key: String) -> Icon? {
        if let hit = icons[key] { return hit }
        guard !checkedDisk.contains(key) else { return nil }
        checkedDisk.insert(key)
        guard let loaded = readDisk(key) else { return nil }
        // Not during a view update: the next run loop, so observation sees it cleanly.
        Task { @MainActor in self.icons[key] = loaded }
        return loaded
    }

    /// Ask the Mac, unless it was asked recently or is being asked now.
    func refresh(key: String, fetch: @escaping () async throws -> ProjectIconResult?) {
        if inflight.contains(key) { return }
        if let at = fetchedAt[key], Date().timeIntervalSince(at) < Self.freshFor { return }
        inflight.insert(key)
        Task { @MainActor in
            defer { inflight.remove(key) }
            guard let result = try? await fetch() else { return } // keep what was there
            fetchedAt[key] = Date()
            let icon: Icon?
            switch result {
            case let .image(dataUri):
                icon = decodeDataURI(dataUri).map(Icon.image)
            case let .kind(k):
                icon = .kind(k)
            }
            guard let icon, icons[key] != icon else { return }
            icons[key] = icon
            writeDisk(key, icon)
        }
    }

    // MARK: Disk

    private func file(_ key: String, _ ext: String) -> URL? {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir?.appendingPathComponent("\(name.prefix(32)).\(ext)")
    }

    private func readDisk(_ key: String) -> Icon? {
        if let url = file(key, "png"), let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return .image(img)
        }
        if let url = file(key, "kind"), let k = try? String(contentsOf: url, encoding: .utf8), !k.isEmpty {
            return .kind(k)
        }
        return nil
    }

    private func writeDisk(_ key: String, _ icon: Icon) {
        switch icon {
        case let .image(img):
            guard let url = file(key, "png"), let data = img.pngData() else { return }
            try? data.write(to: url, options: .atomic)
            if let other = file(key, "kind") { try? FileManager.default.removeItem(at: other) }
        case let .kind(k):
            guard let url = file(key, "kind") else { return }
            try? k.write(to: url, atomically: true, encoding: .utf8)
            if let other = file(key, "png") { try? FileManager.default.removeItem(at: other) }
        }
    }
}
