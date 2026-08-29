import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "dev.superagent.ios", category: "pair")
import UIKit

/// Turns a scanned QR (or pasted link) into a paired Mac: connect through the
/// relay with the QR's secret, introduce ourselves, wait for the Accept click.
enum PairFlow {
    enum Failure: LocalizedError {
        case badLink, machineOffline, rejected(String), timedOut, transport(String)
        var errorDescription: String? {
            switch self {
            case .badLink: "That isn't a SuperAgent pairing code."
            case .machineOffline: "Your Mac isn't reachable right now. Is SuperAgent open and online?"
            case .rejected(let r): r == "pairing-closed"
                ? "The pairing was cancelled or expired on the Mac. Show the code again and retry."
                : "The Mac refused: \(r)."
            case .timedOut: "No answer from the Mac. Tap Accept on it within two minutes."
            case .transport(let m): "Couldn't reach the relay: \(m)"
            }
        }
    }

    /// Resolves once the Mac accepted; throws with a message worth showing.
    @MainActor
    static func pair(payload: PairPayload) async throws -> PairedMachine {
        guard let secret = payload.secret, secret.count == 32 else { throw Failure.badLink }
        let attempt = Attempt(payload: payload, secret: secret)
        return try await attempt.run()
    }

    /// All the mutable state of one pairing attempt, isolated to the main actor.
    @MainActor
    private final class Attempt {
        private let payload: PairPayload
        private let secret: Data
        private var sealer: Sealer
        private var opener: Opener
        private var transport: RelayTransport?
        private var cont: CheckedContinuation<PairedMachine, Error>?
        private let device: DeviceInfo

        init(payload: PairPayload, secret: Data) {
            self.payload = payload
            self.secret = secret
            let keys = DeviceKeys(secret: secret, machineId: payload.m)
            sealer = Sealer(key: keys.p2m, aad: aad(machineId: payload.m, direction: .p2m))
            opener = Opener(key: keys.m2p, aad: aad(machineId: payload.m, direction: .m2p))
            device = DeviceInfo(id: DeviceIdentity.id, name: UIDevice.current.name, model: Attempt.modelIdentifier(), pushToken: nil)
        }

        func run() async throws -> PairedMachine {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<PairedMachine, Error>) in
                cont = c
                let t = RelayTransport { [weak self] event in
                    Task { @MainActor in self?.handle(event) }
                }
                transport = t
                t.connect(relay: payload.relay, machineId: payload.m)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(150))
                    self?.finish(.failure(Failure.timedOut))
                }
            }
        }

        private func handle(_ event: RelayTransport.Event) {
            log.info("event \(String(describing: event).prefix(60), privacy: .public)")
            switch event {
            case .opened:
                guard let json = try? JSONEncoder().encode(ClientFrame.pair(device: device)),
                      let text = String(data: json, encoding: .utf8),
                      let sealed = try? sealer.seal(text) else { return finish(.failure(Failure.badLink)) }
                let fp = SHA256.hash(data: secret).prefix(4).map { String(format: "%02x", $0) }.joined()
                log.info("pair: secretFp=\(fp, privacy: .public) m=\(self.payload.m.prefix(8), privacy: .public) frame=\(sealed.prefix(24), privacy: .public) len=\(sealed.count)")
                transport?.send(sealed)
            case .text(let text):
                if text.hasPrefix("{") {
                    if text.contains("offline") { finish(.failure(Failure.machineOffline)) }
                    return
                }
                guard let plain = opener.open(text), let data = plain.data(using: .utf8),
                      let frame = try? JSONDecoder().decode(ServerFrame.self, from: data) else { return }
                switch frame {
                case let .paired(token, machine):
                    finish(.success(PairedMachine(
                        id: payload.m, name: machine.name, relay: payload.relay,
                        deviceId: device.id, secret: secret, token: token, pairedAt: Date())))
                case .bye(let reason):
                    finish(.failure(Failure.rejected(reason)))
                default:
                    break
                }
            case .closed(let code, let reason):
                if code == 4404 { finish(.failure(Failure.machineOffline)) }
                else { finish(.failure(Failure.transport(reason.isEmpty ? "connection closed" : reason))) }
            }
        }

        private func finish(_ r: Result<PairedMachine, Error>) {
            guard let c = cont else { return }
            if case .failure(let e) = r { log.error("pairing failed: \(e.localizedDescription, privacy: .public)") } else { log.info("paired") }
            cont = nil
            transport?.close()
            transport = nil
            c.resume(with: r)
        }

        private static func modelIdentifier() -> String {
            var sys = utsname()
            uname(&sys)
            return withUnsafePointer(to: &sys.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
        }
    }
}
