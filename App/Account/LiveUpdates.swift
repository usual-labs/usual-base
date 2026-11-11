import Foundation

/// A WebSocket to a hosted Base's room, which says when anyone pushes. It reconnects after a drop, with a
/// growing pause, and pings every 30 seconds so the connection stays open.
@MainActor
final class LiveUpdates {
    private let url: URL
    private let token: String
    private let onPush: () -> Void
    private let onConnected: (Bool) -> Void
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?

    init(url: URL, token: String, onPush: @escaping () -> Void, onConnected: @escaping (Bool) -> Void) {
        self.url = url
        self.token = token
        self.onPush = onPush
        self.onConnected = onConnected
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loop?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        onConnected(false)
    }

    private func run() async {
        var pause: Duration = .seconds(2)
        while !Task.isCancelled {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let task = URLSession.shared.webSocketTask(with: request)
            self.task = task
            task.resume()
            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    try? await task.send(.string("ping"))
                }
            }
            var connected = false
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    if !connected {
                        connected = true
                        pause = .seconds(2)
                        onConnected(true)
                    }
                    if case .string(let text) = message, text.contains("\"pushed\"") { onPush() }
                }
            } catch {
                // Dropped or refused; try again below.
            }
            pinger.cancel()
            onConnected(false)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: pause)
            pause = min(pause * 2, .seconds(120))
        }
    }
}
