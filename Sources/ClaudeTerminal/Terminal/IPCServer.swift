import Foundation
import Network

// MARK: - IPC Server (Unix Domain Socket)
// Receives hook events from local Claude Code processes

final class IPCServer {

    static let socketPath = "/tmp/claude-terminal-\(ProcessInfo.processInfo.processIdentifier).sock"
    static let pidFilePath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude-terminal.pid")

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudeterminal.ipc", qos: .userInteractive)

    var onEvent: ((HookEvent) -> Void)?

    // MARK: - Lifecycle

    func start() throws {
        // Clean up any stale socket
        try? FileManager.default.removeItem(atPath: Self.socketPath)

        let params = NWParameters()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Write socket path to PID file for hook scripts to locate
                let info = "\(Self.socketPath)\n"
                try? info.write(toFile: Self.pidFilePath, atomically: true, encoding: .utf8)
            case .failed(let error):
                print("[IPCServer] Failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: Self.socketPath)
        try? FileManager.default.removeItem(atPath: Self.pidFilePath)
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessage(from: connection)
    }

    private func receiveMessage(from connection: NWConnection) {
        // Protocol: 4-byte big-endian length prefix + JSON body
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4, error == nil else {
                connection.cancel()
                return
            }

            let length = data.withUnsafeBytes { ptr in
                ptr.load(as: UInt32.self).bigEndian
            }

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, err in
                guard let body, err == nil else {
                    connection.cancel()
                    return
                }

                self.processMessage(body, connection: connection)
            }
        }
    }

    private func processMessage(_ data: Data, connection: NWConnection) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let event = try? decoder.decode(HookEvent.self, from: data) else {
            sendResponse(HookResponse(success: false, paneID: nil, message: "Invalid JSON"), on: connection)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }

        sendResponse(HookResponse(success: true, paneID: nil, message: nil), on: connection)
    }

    private func sendResponse(_ response: HookResponse, on connection: NWConnection) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(response) else { return }

        var length = UInt32(data.count).bigEndian
        var header = Data(bytes: &length, count: 4)
        header.append(data)

        connection.send(content: header, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - WebSocket Event Server
// Receives hook events from remote (server) Claude Code via WebSocket
// Server hooks do: curl -X POST http://localhost:9901/hook -d '<json>'

final class WebSocketEventServer {

    static let defaultPort: UInt16 = 9901

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudeterminal.ws", qos: .userInteractive)
    private let port: UInt16

    var onEvent: ((HookEvent) -> Void)?

    init(port: UInt16 = defaultPort) {
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleHTTPConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[WebSocketServer] Failed: \(error)")
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Simple HTTP POST handler for /hook

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            // Parse minimal HTTP: extract body after double-CRLF
            if let bodyData = self.extractHTTPBody(from: data) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                if let event = try? decoder.decode(HookEvent.self, from: bodyData) {
                    DispatchQueue.main.async {
                        self.onEvent?(event)
                    }
                }
            }

            // Send 200 OK
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(
                content: response.data(using: .utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }
    }

    private func extractHTTPBody(from data: Data) -> Data? {
        guard let str = String(data: data, encoding: .utf8),
              let range = str.range(of: "\r\n\r\n") else { return nil }
        let bodyStart = str.distance(from: str.startIndex, to: range.upperBound)
        guard bodyStart < data.count else { return nil }
        return data.suffix(from: bodyStart)
    }
}
