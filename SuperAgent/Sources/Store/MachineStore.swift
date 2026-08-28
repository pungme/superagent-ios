import Foundation
import Security

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
        guard let data = read() else { return [] }
        return (try? JSONDecoder().decode([PairedMachine].self, from: data)) ?? []
    }

    static func save(_ machines: [PairedMachine]) {
        guard let data = try? JSONEncoder().encode(machines) else { return }
        write(data)
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

    private static func write(_ data: Data) {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
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
