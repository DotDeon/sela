import Foundation
import Network

/// A local HTTP server that sends one file as an attachment, slowly, so a download is still running when a test acts on it.
final class SlowServer: @unchecked Sendable {
    private let listener: NWListener
    let port: UInt16

    init(bytes: Int = 2_000_000, chunk: Int = 20_000, delay: TimeInterval = 0.05) throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { _, _, _, _ in
                let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"slow.bin\"\r\nContent-Length: \(bytes)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
                func send(_ remaining: Int) {
                    guard remaining > 0 else { return }
                    let size = min(chunk, remaining)
                    connection.send(content: Data(repeating: 7, count: size), completion: .contentProcessed { error in
                        guard error == nil else { return }
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { send(remaining - size) }
                    })
                }
                send(bytes)
            }
        }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    var url: URL { URL(string: "http://127.0.0.1:\(port)/slow.bin")! }

    deinit { listener.cancel() }
}
