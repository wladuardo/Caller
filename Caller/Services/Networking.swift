import Foundation

protocol WebSocketClient {
    func connect() async throws
    func send(_ message: SignalingMessage) async throws
    func disconnect()
    var messages: AsyncStream<SignalingMessage> { get }
}

final class URLSessionWebSocketClient: WebSocketClient {
    private let url: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private var continuation: AsyncStream<SignalingMessage>.Continuation?

    lazy var messages: AsyncStream<SignalingMessage> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    init(url: URL) {
        self.url = url
    }

    func connect() async throws {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        webSocketTask = task
        receiveLoop()
    }

    func send(_ message: SignalingMessage) async throws {
        let data = try JSONEncoder().encode(message)
        let string = String(decoding: data, as: UTF8.self)
        try await webSocketTask?.send(.string(string))
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                break
            case .success(let message):
                if case .string(let string) = message,
                   let data = string.data(using: .utf8) {
                    Task { @MainActor [weak self] in
                        guard let self,
                              let decoded = try? JSONDecoder().decode(SignalingMessage.self, from: data) else { return }
                        self.continuation?.yield(decoded)
                    }
                }
                self.receiveLoop()
            @unknown default:
                self.receiveLoop()
            }
        }
    }
}
