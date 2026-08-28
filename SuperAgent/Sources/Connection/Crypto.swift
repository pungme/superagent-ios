import CryptoKit
import Foundation

// Mirrors superagent-desktop/app/src/main/companion/crypto.ts (SPEC §2.5).
//
//   key_m2p = HKDF-SHA256(k, salt = machineId, info = "sa-m2p")   Mac → phone
//   key_p2m = HKDF-SHA256(k, salt = machineId, info = "sa-p2m")   phone → Mac
//   frame   = base64( nonce(12) ‖ ciphertext ‖ tag(16) )
//   nonce   = connectionSalt(4) ‖ counter(8, big-endian), counter strictly increasing
//   AAD     = machineId ‖ direction

struct DeviceKeys: Sendable {
    let m2p: SymmetricKey
    let p2m: SymmetricKey

    init(secret: Data, machineId: String) {
        let ikm = SymmetricKey(data: secret)
        let salt = Data(machineId.utf8)
        m2p = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("sa-m2p".utf8), outputByteCount: 32)
        p2m = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("sa-p2m".utf8), outputByteCount: 32)
    }
}

enum Direction: String { case m2p, p2m }

func aad(machineId: String, direction: Direction) -> Data {
    Data((machineId + direction.rawValue).utf8)
}

/// Seals frames the phone sends: fresh 4-byte salt per connection, counter from 1.
struct Sealer {
    private let key: SymmetricKey
    private let aad: Data
    private let salt: Data
    private var counter: UInt64 = 0

    init(key: SymmetricKey, aad: Data, salt: Data? = nil) {
        self.key = key
        self.aad = aad
        self.salt = salt ?? Data((0..<4).map { _ in UInt8.random(in: 0...255) })
    }

    mutating func seal(_ plaintext: String) throws -> String {
        counter += 1
        var nonce = Data(salt)
        withUnsafeBytes(of: counter.bigEndian) { nonce.append(contentsOf: $0) }
        let box = try ChaChaPoly.seal(Data(plaintext.utf8), using: key, nonce: try ChaChaPoly.Nonce(data: nonce), authenticating: aad)
        return box.combined.base64EncodedString()
    }
}

/// Opens frames the Mac sends: pins the salt on the first frame, refuses replays.
struct Opener {
    private let key: SymmetricKey
    private let aad: Data
    private var salt: Data?
    private var last: UInt64 = 0

    init(key: SymmetricKey, aad: Data) {
        self.key = key
        self.aad = aad
    }

    mutating func open(_ frame: String) -> String? {
        guard let data = Data(base64Encoded: frame), data.count >= 12 + 16 else { return nil }
        let nonce = data.prefix(12)
        let frameSalt = nonce.prefix(4)
        let counter = nonce.dropFirst(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        if let salt, salt != frameSalt { return nil }
        if counter <= last { return nil }
        guard let box = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(box, using: key, authenticating: aad),
              let text = String(data: plain, encoding: .utf8) else { return nil }
        if salt == nil { salt = Data(frameSalt) }
        last = counter
        return text
    }
}

/// The 6-digit code both screens show: first 16 hex digits of SHA-256(k ‖ machineId), mod 10^6.
func pairingCode(secret: Data, machineId: String) -> String {
    var h = SHA256()
    h.update(data: secret)
    h.update(data: Data(machineId.utf8))
    let hex = h.finalize().map { String(format: "%02x", $0) }.joined()
    let n = UInt64(hex.prefix(16), radix: 16) ?? 0
    return String(format: "%06llu", n % 1_000_000)
}
