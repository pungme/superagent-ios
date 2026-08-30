import AVFoundation
import Foundation
import Observation
import Speech

/// Push-to-talk dictation, on device where the system allows it. Mirrors the
/// desktop's hold-the-mic-key flow: start, speak, stop, the words land in the
/// composer for review before sending.
@MainActor
@Observable
final class Dictation {
    private(set) var listening = false
    private(set) var transcript = ""
    private(set) var error: String?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var available: Bool { recognizer?.isAvailable ?? false }

    func start() async {
        guard !listening else { return }
        error = nil
        transcript = ""
        let speechOK = await Self.speechAuthorized()
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK, let recognizer, recognizer.isAvailable else {
            error = "Dictation isn't available. Check microphone and speech permissions in Settings."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // A device with no usable input reports a zero format, and
            // installTap raises an Objective-C exception on one, which no
            // Swift catch will save us from. Bail out with a message instead.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                error = "No microphone is available on this device."
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            // Removing first: a start that failed after installing would
            // otherwise leave a tap behind, and a second tap on the same bus
            // is another uncatchable exception.
            input.removeTap(onBus: 0)
            // @Sendable on both callbacks below, deliberately. This class is
            // @MainActor, so a plain closure written here inherits that
            // isolation, and both of these are called somewhere else: the tap
            // on AVFAudio's realtime queue, the recognition callback on
            // Speech's. The concurrency runtime checks, finds the wrong
            // executor, and traps the process.
            nonisolated(unsafe) let sink = req
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                sink.append(buffer)
            }
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, err in
                // Read what we need here, on Speech's own queue: the result
                // itself is not Sendable, a String and a Bool are.
                let text = result?.bestTranscription.formattedString
                let finished = err != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch {
            self.error = "Couldn't start the microphone: \(error.localizedDescription)"
            stop()
        }
    }

    /// Both of these build their closure OUTSIDE the actor on purpose.
    ///
    /// A closure written inside a `@MainActor` type inherits that isolation, and
    /// the concurrency runtime checks it when the closure runs. Audio taps run on
    /// AVFAudio's realtime queue and recognition results on Speech's own queue,
    /// so the check fails and traps the process — the microphone crashed the app
    /// as soon as the first buffer arrived. Made here, they carry no isolation;
    /// anything that touches the app's state hops back with `Task { @MainActor }`.
    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        into request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(
        _ recognizer: SFSpeechRecognizer,
        _ request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    /// Off the main actor on purpose. `requestAuthorization` answers on TCC's
    /// own queue, and a @MainActor-isolated completion there trips the
    /// concurrency runtime's executor check and traps the process, which is
    /// what tapping the microphone used to do.
    private nonisolated static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    func stop() {
        guard listening || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
