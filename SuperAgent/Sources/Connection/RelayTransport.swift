import Foundation

/// One WebSocket to the relay's client endpoint for a machine. Delivers raw text
/// frames (ciphertext, or the relay's own `{"t":"offline"}`) and a close reason.
final class RelayTransport: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case opened
        case text(String)
        case closed(code: Int, reason: String)
    }

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private let handler: @Sendable (Event) -> Void
    private var closedOnce = false

    init(handler: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
    }

    func connect(relay: String, machineId: String) {
        let base = relay.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: "\(base)/c/\(machineId)") else {
            handler(.closed(code: -1, reason: "bad relay URL"))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let t = session.webSocketTask(with: request)
        task = t
        t.resume()
        receiveLoop(t)
    }

    func send(_ text: String) {
        task?.send(.string(text)) { [weak self] error in
            if let error { self?.finish(code: -1, reason: error.localizedDescription) }
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        finish(code: 1000, reason: "closed")
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let s) = message { self.handler(.text(s)) }
                else if case .data(let d) = message, let s = String(data: d, encoding: .utf8) { self.handler(.text(s)) }
                self.receiveLoop(t)
            case .failure(let error):
                let code = (error as NSError).code
                self.finish(code: code, reason: error.localizedDescription)
            }
        }
    }

    private func finish(code: Int, reason: String) {
        if closedOnce { return }
        closedOnce = true
        handler(.closed(code: code, reason: reason))
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        handler(.opened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        finish(code: closeCode.rawValue, reason: text)
    }
}
