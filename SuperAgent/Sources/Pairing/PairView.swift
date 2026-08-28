import SwiftUI
import VisionKit

/// Scan the QR on the Mac (or paste the copied link), then wait for Accept.
struct PairView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case scanning
        case pairing(PairPayload)
        case failed(String)
    }

    @State private var phase: Phase
    @State private var pasted = ""

    init(initial: PairPayload? = nil) {
        _phase = State(initialValue: initial.map { .pairing($0) } ?? .scanning)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning: scanning
                case .pairing(let payload): pairing(payload)
                case .failed(let message): failed(message)
                }
            }
            .navigationTitle("Pair a Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var scanning: some View {
        VStack(spacing: 16) {
            if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                QRScanner { text in accept(text) }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .frame(maxHeight: 360)
                Text("On the Mac: Settings → Phone → Show pairing code")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("No camera here", systemImage: "camera.fill",
                                       description: Text("Use “Copy link” under the code on the Mac and paste it below."))
            }
            HStack {
                TextField("Or paste the pairing link", text: $pasted)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Pair") { accept(pasted) }
                    .buttonStyle(.borderedProminent)
                    .disabled(pasted.isEmpty)
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 12)
    }

    private func pairing(_ payload: PairPayload) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Pairing with \(payload.name)…").font(.headline)
            Text("Make sure the Mac shows this code, then tap Accept there.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            if let secret = payload.secret {
                let code = pairingCode(secret: secret, machineId: payload.m)
                Text("\(code.prefix(3)) \(code.suffix(3))")
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .padding(.top, 8)
            }
            Spacer()
        }
        .task {
            do {
                let machine = try await PairFlow.pair(payload: payload)
                app.add(machine)
                dismiss()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text("Pairing didn't finish").font(.headline)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            Button("Try again") { pasted = ""; phase = .scanning }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func accept(_ text: String) {
        guard case .scanning = phase else { return }
        if let payload = PairPayload.parse(text) { phase = .pairing(payload) }
        else { phase = .failed("That isn't a SuperAgent pairing code.") }
    }
}

/// VisionKit's scanner, limited to QR codes; reports the first code seen.
struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var fired = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let s = b.payloadStringValue, s.contains("superagent://pair") {
                    fired = true
                    dataScanner.stopScanning()
                    onCode(s)
                    return
                }
            }
        }
    }
}
