import Foundation
import Security
import os

private let log = Logger(subsystem: "dev.superagent.ios", category: "store")

/// A Mac this phone is paired with. Everything needed to reach and decrypt it.
struct PairedMachine: Codable, Identifiable, Hashable, Sendable {
    var id: String          // machineId
    var name: String
    var relay: String
    var deviceId: String
    var secret: Data
    var token: String
    var pairedAt: Date
}

/// Paired Macs live in the Keychain (not UserDefaults): they hold encryption keys.
/// Readable after first unlock so a notification action can answer while the phone is locked.
enum MachineStore {
    private static let service = "dev.superagent.machines"
    private static let account = "paired"

    static func load() -> [PairedMachine] {
        guard let data = read() ?? readFile() else { return [] }
        return (try? JSONDecoder().decode([PairedMachine].self, from: data)) ?? []
    }

    static func save(_ machines: [PairedMachine]) {
        guard let data = try? JSONEncoder().encode(machines) else { return }
        if !write(data) {
            // The keychain can refuse (simulator without entitlements, restricted
            // profiles). Fall back to a protected file so pairing still sticks.
            writeFile(data)
        }
    }

    // MARK: File fallback (complete-until-first-unlock protection)

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("machines.json")
    }

    private static func readFile() -> Data? { try? Data(contentsOf: fileURL) }

    private static func writeFile(_ data: Data) {
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("machine store: file write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func upsert(_ m: PairedMachine) {
        var all = load().filter { $0.id != m.id }
        all.append(m)
        save(all)
    }

    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    // MARK: Keychain

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    private static func read() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        return status == errSecSuccess ? out as? Data : nil
    }

    @discardableResult
    private static func write(_ data: Data) -> Bool {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        if status != errSecSuccess { log.error("machine store: keychain write failed (\(status))") }
        return status == errSecSuccess
    }
}

/// A stable id for this phone across launches (Keychain-backed so reinstalls keep it).
enum DeviceIdentity {
    private static let key = "dev.superagent.deviceId"
    static var id: String {
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString.lowercased()
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}
